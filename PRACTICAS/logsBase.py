from firebase import firebase

firebase = firebase.FirebaseApplication("https://virtual-ej-default-rtdb.firebaseio.com/",None)

i = 0
try:
    while True:
        with open('numero.txt', 'r') as num:
            i = int(num.readline())

        with open("logs/access.log", "r") as archivo:
            h =1
            linea = archivo.readline()
            while linea:
                #print(f"Línea {h}: {linea}")
                # Aquí puedes agregar tu código para procesar la línea actual
                # y almacenar la información en una variable para evitar leerla nuevamente
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
except KeyboardInterrupt:
    print("\nProgram interrupted by user. Exiting...")