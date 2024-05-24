terraform {
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "kubernetes" {
  config_path = "~/.kube/config"  # Ruta a tu archivo de configuración de Kubernetes
}


resource "kubernetes_config_map" "loki_config" {
  metadata {
    name = "loki-config"
  }

  data = {
    "local-config.yaml" = <<-EOT
      auth_enabled: false

      server:
        http_listen_port: 3100
        grpc_listen_port: 9096

      query_scheduler:
        max_outstanding_requests_per_tenant: 4096
      frontend:
        max_outstanding_per_tenant: 4096

      common:
        instance_addr: 127.0.0.1
        path_prefix: /tmp/loki
        storage:
          filesystem:
            chunks_directory: /tmp/loki/chunks
            rules_directory: /tmp/loki/rules
        replication_factor: 1
        ring:
          kvstore:
            store: inmemory

      query_range:
        results_cache:
          cache:
            embedded_cache:
              enabled: true
              max_size_mb: 100

      schema_config:
        configs:
          - from: 2020-10-24
            store: boltdb-shipper
            object_store: filesystem
            schema: v11
            index:
              prefix: index_
              period: 24h

      ruler:
        alertmanager_url: http://localhost:9093

      analytics:
       reporting_enabled: false    
    EOT
  }
}

resource "kubernetes_config_map" "promtail_config" {
  metadata {
    name = "promtail-config"
  }

  data = {
    "config.yml" = <<-EOT
      server:
        http_listen_port: 9080
        grpc_listen_port: 0

      positions:
        filename: /tmp/positions.yaml

      clients:
        - url: http://localhost:3100/loki/api/v1/push

      scrape_configs:
        - job_name: nginx
          static_configs:
            - targets:
                - localhost
              labels:
                job: nginx
                __path__: /var/log/nginx/*log      
    EOT
  }
}

resource "kubernetes_config_map" "nginx_config" {
  metadata {
    name = "nginx-config"
  }

  data = {
    "nginx.conf" = <<-EOT
      error_log /var/log/nginx/error.log warn;
      pid /var/run/nginx.pid;
      
      events {
        worker_connections 1024;
      }

      http {
        include /etc/nginx/mime.types;
        default_type application/octet-stream;
        sendfile on;
        keepalive_timeout 65;

        access_log /var/log/nginx/access.log;
        
        server {
          listen 80;
          location / {
            proxy_pass http://app-service:5000;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;
          }
        }
      }
    EOT
  }
}


resource "kubernetes_deployment" "proyecto_app" {
  metadata {
    name = "proyecto-app"
    labels = {
      app = "proyecto-app"
    }
  }

  spec {
    replicas = 3
    selector {
      match_labels = {
        app = "proyecto-app"
      }
    }
    template {
      metadata {
        labels = {
          app = "proyecto-app"
        }
      }
      spec {  
        container {
          name  = "holamundo-container"
          image = "practicas-app:latest"
          image_pull_policy = "Never"
          port {
            container_port = 5000
          }
        }              
      }
    }
  }
}

resource "kubernetes_deployment" "proyecto_nginx" {
  metadata {
    name = "proyecto-nginx"
    labels = {
      app = "proyecto-nginx"
    }
  }

  spec {
    replicas = 1
    selector {
      match_labels = {
        app = "proyecto-nginx"
      }
    }
    template {
      metadata {
        labels = {
          app = "proyecto-nginx"
        }
      }
      spec {            
        container {
          name  = "nginx-container"
          image = "nginx:latest"
          image_pull_policy = "Never"          
          port {
            container_port = 80 
          }
          volume_mount {
            mount_path = "/etc/nginx/nginx.conf"
            sub_path   = "nginx.conf"
            name       = "nginx-config-volume"
          }     
          volume_mount {
            name       = "log-volume"
            mount_path = "/var/log/nginx"
          }               
        }

        volume {
          name = "nginx-config-volume"

          config_map {
            name = kubernetes_config_map.nginx_config.metadata[0].name
          }
        }

        volume {
          name = "log-volume"

          empty_dir {}
        }

        container {
          name  = "grafana-container"
          image = "grafana/grafana-oss:latest"
          image_pull_policy = "Never"          
          port {
            container_port = 3000 
          }                 
        }
        
        
        container {
          name  = "promtail-container"
          image = "grafana/promtail:2.9.0"
          image_pull_policy = "Never"   
          args = ["-config.file=/etc/promtail/config.yml"]    
                                 
          volume_mount {
            name = "log-volume"
            mount_path = "/var/log/nginx"
          }
          volume_mount {
            mount_path = "/etc/promtail/config.yml"
            sub_path   = "config.yml"
            name = "promtail-config"                        
          }    
        }
        
        volume {
          name = "promtail-config"

          config_map {
            name = kubernetes_config_map.promtail_config.metadata[0].name
          }
        }

        container {
          name  = "loki-container"
          image = "grafana/loki:2.9.0"
          image_pull_policy = "Never"   
          args = ["-config.file=/etc/loki/local-config.yaml"]        

          port {
            container_port = 3100 
          }
          volume_mount {
            mount_path = "/etc/loki/local-config.yaml"            
            sub_path   = "local-config.yaml"
            name = "loki-config"            
          }  
          volume_mount {
            mount_path = "/loki"
            name       = "loki-storage-volume"
          }
        }

        volume {
          name = "loki-config"

          config_map {
            name = kubernetes_config_map.loki_config.metadata[0].name
          }
        }

        volume {
          name = "loki-storage-volume"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service" "app_service" {
  metadata {
    name = "app-service"
  }

  spec {
    selector = {
      app = kubernetes_deployment.proyecto_app.spec.0.template.0.metadata.0.labels["app"]
    }
    port {
      port        = 5000
      target_port = 5000
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_service" "nginx_service" {
  metadata {
    name = "nginx-service"
  }

  spec {
    selector = {
      app = kubernetes_deployment.proyecto_nginx.spec.0.template.0.metadata.0.labels["app"]
    }
    port {
      port        = 81
      target_port = 80
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_service" "grafana_service" {
  metadata {
    name = "grafana-service"
  }

  spec {
    selector = {
      app = kubernetes_deployment.proyecto_nginx.spec.0.template.0.metadata.0.labels["app"]
    }
    port {
      port        = 3000
      target_port = 3000
    }
    type = "LoadBalancer"
  }
}

resource "kubernetes_service" "loki_service" {
  metadata {
    name = "loki-service"
  }

  spec {
    selector = {
      app = kubernetes_deployment.proyecto_nginx.spec.0.template.0.metadata.0.labels["app"]
    }
    port {
      port        = 3100
      target_port = 3100
    }
    type = "LoadBalancer"
  }
}