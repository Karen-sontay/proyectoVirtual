from kubernetes import client, config, stream
from firebase import firebase

firebase = firebase.FirebaseApplication("https://virtual-ej-default-rtdb.firebaseio.com/",None)

i = 0

def get_nginx_access_logs(namespace, pod_name, container_name=None):
    # Configura el acceso al clúster de Kubernetes
    config.load_kube_config()  # Asegúrate de que KUBECONFIG esté configurado correctamente

    # Crea una instancia del API de CoreV1
    v1 = client.CoreV1Api()

    # Comando para leer el archivo de logs
    command = ["cat", "/var/log/nginx/access.log"]

    # Ejecutar el comando en el contenedor del pod
    try:
        if container_name:
            exec_command = stream.stream(
                v1.connect_get_namespaced_pod_exec,
                pod_name,
                namespace,
                container=container_name,
                command=command,
                stderr=True, stdin=False,
                stdout=True, tty=False
            )
        else:
            exec_command = stream.stream(
                v1.connect_get_namespaced_pod_exec,
                pod_name,
                namespace,
                command=command,
                stderr=True, stdin=False,
                stdout=True, tty=False
            )
        return exec_command
    except client.exceptions.ApiException as e:
        print(f"An error occurred: {e}")
        return None
    

if __name__ == "__main__":
    namespace = "default"  # Cambia esto si tu pod está en un namespace diferente
    pod_name = "proyecto-nginx-5d8789ff46-w5rq2"  # Cambia esto al nombre de tu pod
    container_name = "nginx-container"  # Cambia esto al nombre de tu contenedor, si es necesario

    while True:
        logs = get_nginx_access_logs(namespace, pod_name, container_name)
        if logs:
            print(logs)
        
        with open('logs/access.log', 'w') as f:
            f.write(str(logs))
        
        with open('numero.txt', 'r') as num:
            i = int(num.readline())
        
        with open("logs/access.log", "r") as archivo:
            h =1
            linea = archivo.readline()
            while linea:

                if(h >= i):
                    h += 1
                    if(linea != ''):
                        i += 1
                        #METODO POST.
                        resultado=firebase.post('/ejerciciov/logs/', linea)
                        linea = archivo.readline()
                else:
                    h += 1
                    linea = archivo.readline()
        
        with open('numero.txt', 'w') as f:
            f.write(str(i))