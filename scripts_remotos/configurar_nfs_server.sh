#!/bin/bash
#
# Script de configuración del servicio nfs_server.
#

msgEstado() { echo -e "\t\e[1m\e[32m[*] \e[39m$@\e[0m" 1>&2; }
msgError() { echo -e "\t\e[1m\e[31m[!] \e[39m$@\e[0m" 1>&2; }

instalarPaquete() {
    if [[ ! $(dpkg -s $1 2> /dev/null | grep Status) == "Status: install ok installed" ]]; then
        msgEstado "Instalando el paquete '${1}'..."
        DEBIAN_FRONTEND=noninteractive apt-get -yq install $1

        if [[ $? -ne 0 ]]; then
            msgError "Error instalando '${1}'."
            exit 1
        fi
    fi
}

msgEstado "Leyendo fichero de configuración..."
exports=()
num_err=0
while read linea; do
    if [[ ! $linea =~ ^$ ]] && [[ ! $linea =~ ^[\ \t]*$ ]]; then
        if [[ $linea =~ ^[\ \t]*(/[a-zA-Z0-9/_\.\-]*)[\ \t]*$ ]]; then
            exports+=(${BASH_REMATCH[1]})

            if [[ ! -d ${BASH_REMATCH[1]} ]]; then
                msgError "'${BASH_REMATCH[1]}' no existe o no es un directorio."
                ((num_err++))
            fi
        else
            msgError "Formato de directorio incorrecto: $linea"
            exit 1
        fi
    fi
done < ${0/.sh/.conf}

if [[ $num_err -gt 0 ]]; then
    exit 1
fi

instalarPaquete nfs-common
instalarPaquete nfs-kernel-server

for directorio in $exports; do
    if [[ `grep $directorio /etc/exports 2> /dev/null | grep -vP "^[ \t]*#" 2> /dev/null` =~ ^$ ]]; then
        msgEstado "Añadiendo '$directorio' como export..."
        echo "$directorio *(rw,sync,no_subtree_check)" >> /etc/exports
        if [[ $? -ne 0 ]]; then
            msgError "No se ha podido añadir el export."
            exit 1
        fi
    else
	msgError "'$directorio' ya está exportado, ignorado."
    fi
done

msgEstado "Reiniciando el servidor nfs..."
service nfs-kernel-server restart
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido reiniciar."
    exit 1
fi
