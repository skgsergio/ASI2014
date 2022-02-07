#!/bin/bash
#
# Administración de Sistemas UNIX
# Práctica 2014
#
# Sergio Cónde Gómez
#

# Parametros para ssh y scp:
#  - Evitar leer stdin (-n).
#  - Definir el loglevel en ERROR.
#  - Reducción del timeout.
#  - Evitar la comprobación de fingerprint (bastante inseguro pero se pide que no exista
# interacción con el usuario)
SSH="ssh -n -oLogLevel=ERROR -oConnectTimeout=1 -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no"
SCP="scp -oLogLevel=ERROR -oConnectTimeout=1 -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no"

# Lista de servicios que podemos configurar.
SERVICIOS=(mount raid lvm nis_server nis_client nfs_server nfs_client backup_client backup_server)

# Path donde se va a trabajar.
AUX_DIR="/etc/configurar_cluster"

# Funciones para los mensajes
msgEstado() { echo -e "\e[1m\e[32m[*] \e[39m$@\e[0m" 1>&2; }
msgError() { echo -e "\e[1m\e[31m[!] \e[39m$@\e[0m" 1>&2; }

# Impresión de errores en ficheros.
errorFichero() {
    error_fichero=$1; shift
    error_linea=$1; shift

    if [[ $error_linea -gt 0 ]]; then
        echo -e "[$error_fichero - Ln: $error_linea]\n\t$@\n" 1>&2
    else
        echo -e "[$error_fichero]\n\t$@\n" 1>&2
    fi

    ((num_errores++))
}

# Comprobación del numero de lineas en ficheros de cada servicio.
comprobarLineas() {
    lineas_fichero=$(sed '/^$/d' $2 | wc -l)

    case $1 in
        mount)         tipo="=";  lineas_esperadas=2;;
        raid)          tipo="=";  lineas_esperadas=3;;
        lvm)           tipo=">="; lineas_esperadas=2;;
        nis_server)    tipo="=";  lineas_esperadas=1;;
        nis_client)    tipo="=";  lineas_esperadas=2;;
        nfs_server)    tipo=">="; lineas_esperadas=1;;
        nfs_client)    tipo=">="; lineas_esperadas=1;;
        backup_client) tipo="=";  lineas_esperadas=4;;
        backup_server) tipo="=";  lineas_esperadas=1;;
    esac

    if [[ $tipo == "=" ]] && [[ ! $lineas_fichero -eq $lineas_esperadas ]]; then
        errorFichero $2 0 "Se esperaban $lineas_esperadas lineas y se han encontrado $lineas_fichero."
    elif [[ $tipo == ">=" ]] && [[ ! $lineas_fichero -ge $lineas_esperadas ]]; then
        errorFichero $2 0 "Se esperaban $lineas_esperadas o más lineas y se han encontrado $lineas_fichero."
    fi
}

# Comprobamos que el usuario especifique un fichero principal
if [[ $1 == "" ]]; then
    echo "Uso: $0 fichero_principal" 2>&1
    exit 1
elif [[ ! -f $1 ]]; then
    echo "$0: '$1' no existe o no es un fichero." 2>&1
    exit 1
else
    fichero_principal=$1
fi

# Lista de servicios leidos de la configuración.
configs=()

# Lista de hosts unicos, para actualizar la cache de apt antes de empezar.
hosts_unicos=()

# Lectura y validación del fichero principal y los ficheros de servicios.
num_linea=1
num_errores=0

msgEstado "Leyendo el fichero de configuración..."
while read linea; do
    # Ignoramos lineas vacías y con comentarios.
    if [[ ! $linea =~ ^[[:space:]]*# ]] && [[ ! $linea =~ ^[[:space:]]*$ ]]; then
        # Obtenemos 3 campos separados que no contengan espacios o #, además permitimos
	# un comentario justo despues de los campos.
        if [[ $linea =~ ^([a-zA-Z0-9_\.\-]*)[\ \t]*([a-zA-Z0-9_\.\-]*)[\ \t]*([a-zA-Z0-9/_\.\-]*)[\ \t]*( \#.*)?$ ]]; then
            campos=("${BASH_REMATCH[@]}")

            # Comprobamos la conectividad de la máquina (que el host o ip especificado sea bueno)
	    # y de paso creamos una carpeta auxiliar en ella.
            if ! $SSH root@${campos[1]} "mkdir -p ${AUX_DIR}"; then
                errorFichero $1 $num_linea "La máquina '${campos[1]}' no responde."
            fi

            # Comprobamos que el servicio (segundo campo) está en la lista de servicios
	    # que podemos configurar.
            if [[ ! " ${SERVICIOS[@]} " =~ " ${campos[2]} " ]]; then
                errorFichero $1 $num_linea "El servicio '${campos[2]}' es incorrecto.\n\tServicios admitidos: ${SERVICIOS[@]}"
                serv_err=1
            fi

            # Comprobamos que el fichero de configuración existe.
            if [[ ! -f ${campos[3]} ]]; then
                errorFichero $1 $num_linea "El fichero de configuración '${campos[3]}' no existe."
                conf_err=1
            fi

            # Si el servicio es correcto y el fichero de configuración existe comprobamos
	    # que posea el número de lineas necesario.
            if [[ $serv_err -ne 1 ]] && [[ $conf_err -ne 1 ]]; then
                comprobarLineas ${campos[2]} ${campos[3]}
            fi

	    # Guardamos el host en la lista de unicos si no está.
	    if [[ ! " ${hosts_unicos[@]} " =~ " ${campos[1]} " ]]; then
		hosts_unicos+=(${campos[1]})
	    fi

            # Guardamos la linea de configuración (aunque existan errores).
            configs+=(${campos[1]} ${campos[2]} ${campos[3]})

            unset campos serv_err conf_err
        else
            errorFichero $1 $num_linea "Error de sintaxis: $linea\n\tFormato esperado: maquina-destino nombre-servicio fichero-configuracion ([a-zA-Z0-9_-.] [a-zA-Z0-9_-.] [a-zA-Z0-9_-./])"
        fi
    fi

    ((num_linea++))
done < $fichero_principal

num_configs=$((${#configs[@]} / 3))

# Abortamos la ejecución si hay errores en los ficheros de configuración o si
# alguna máquina no responde. También si no hay lineas de configuración.
if [[ $num_errores -gt 0 ]]; then
    msgError "Proceso abortado con $num_errores errores."
    exit 1
elif [[ ! $num_configs -gt 0 ]]; then
    msgError "El fichero no contiene ninguna línea de configuración."
    exit 1
else
    msgEstado "Leidas $num_configs líneas de configuración."
fi

# Iteramos el array de hosts unicos para ejecutar una actualización de la cache de apt.
for ((i=0; i < ${#hosts_unicos[@]}; i++)); do
    msgEstado "Actualizando cache de apt en '${hosts_unicos[i]}'..."
    #$SSH root@${hosts_unicos[i]} "export DEBIAN_FRONTEND=noninteractive; apt-get -yq update"

    if [[ $? -ne 0 ]]; then
	msgError "No se ha podido realizar la operación"
	exit 1
    fi
done

# Iteramos el array de servicios leidos (con un hack un poco guarro ya que bash no admite
# arrays multidimensionales) subiendo el script auxiliar y su configuraciín. Si la subida
# es satisfactoria lo ejecutamos.
for ((i=0; i < $num_configs; i++)); do
    cDestino=${configs[$((i*3))]}
    cServicio=${configs[$((i*3 + 1))]}
    cFichero=${configs[$((i*3 + 2))]}

    msgEstado "Configurando '${cServicio}' en '${cDestino}'..."
    $SCP scripts_remotos/configurar_${cServicio}.sh root@${cDestino}:${AUX_DIR}/configurar_${cServicio}.sh > /dev/null
    $SCP ${cFichero} root@${cDestino}:${AUX_DIR}/configurar_${cServicio}.conf > /dev/null
    $SSH root@${cDestino} "cd ${AUX_DIR} && chmod +x configurar_${cServicio}.sh && ./configurar_${cServicio}.sh"

    if [[ $? -ne 0 ]]; then
	msgError "Se ha producido al menos un error, revise la salida anterior para más información."
	exit 1
    fi
done
