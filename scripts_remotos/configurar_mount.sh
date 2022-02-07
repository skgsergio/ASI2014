#!/bin/bash
#
# Script de configuración del servicio mount.
#

msgEstado() { echo -e "\t\e[1m\e[32m[*] \e[39m$@\e[0m" 1>&2; }
msgError() { echo -e "\t\e[1m\e[31m[!] \e[39m$@\e[0m" 1>&2; }

msgEstado "Leyendo fichero de configuración..."
n_linea=0
while read linea; do
    if [[ ! $linea =~ ^$ ]] && [[ ! $linea =~ ^[\ \t]*$ ]]; then
        ((n_linea++))
        if [[ $n_linea -eq 1 ]]; then
            if [[ $linea =~ ^[\ \t]*(/dev/[a-zA-Z0-9/_\.\-]*)[\ \t]*$ ]]; then
                dispositivo=${BASH_REMATCH[1]}
                if [[ ! -b $dispositivo ]]; then
                    msgError "'$dispositivo' no existe o no es un dispositivo de bloques."
                    exit 1
                fi
            else
                msgError "Nombre del dispositivo erroneo: $linea"
                exit 1
            fi
        elif [[ $n_linea -eq 2 ]]; then
            if [[ $linea =~ ^[\ \t]*(/[a-zA-Z0-9/_\.\-]*)[\ \t]*$ ]]; then
                punto_montaje=${BASH_REMATCH[1]}
            else
                msgError "Punto de montaje erroneo: $linea"
                exit 1
            fi
        fi
    fi
done < ${0/.sh/.conf}

msgEstado "Creando punto de montaje '$punto_montaje'..."
mkdir -p $punto_montaje
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido crear el punto de montaje."
    exit 1
fi

msgEstado "Montando dispositivo '$dispositivo'..."
mount $dispositivo $punto_montaje
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido montar el dispositivo."
    exit 1
fi

msgEstado "Detectando sistema de ficheros..."
sistema_ficheros=`grep $dispositivo /proc/mounts 2> /dev/null | awk '{ print $3 }'`

msgEstado "Configurando el automontaje de '$dispositivo' en '$punto_montaje'..."
if [[ ! `grep $dispositivo /etc/fstab 2> /dev/null | grep -vP "^[ \t]*#" 2> /dev/null` =~ ^$ ]]; then
    msgError "El dispositivo ya se encuentra en /etc/fstab"
    exit 1
fi

echo -e "$dispositivo\t$punto_montaje\t$sistema_ficheros\terrors=remount-ro\t0\t2" >> /etc/fstab
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido configurar el automontaje."
    exit 1
fi
