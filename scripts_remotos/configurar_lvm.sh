#!/bin/bash
#
# Script de configuración del servicio lvm.
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
n_linea=0
while read linea; do
    if [[ ! $linea =~ ^$ ]] && [[ ! $linea =~ ^[\ \t]*$ ]]; then
        ((n_linea++))

        if [[ $n_linea -eq 1 ]]; then
            if [[ $linea =~ ^[\ \t]*([a-zA-Z0-9]*)[\ \t]*$ ]]; then
                nombre=${BASH_REMATCH[1]}
            else
                msgError "Nombre erroneo para el grupo: $linea"
                exit 1
            fi
        elif [[ $n_linea -eq 2 ]]; then
            if [[ $linea =~ ^[\ \t]*((/dev/[a-zA-Z0-9/_\.\-]*[\ \t]*)*)$ ]]; then
                lista_dispositivos=${BASH_REMATCH[1]}
                num_dispositivos=`echo -n "$lista_dispositivos" | wc -w`

                num_err=0
                for d in $lista_dispositivos; do
                    if [[ ! -b $d ]]; then
                        msgError "'$d' no existe o no es un dispositivo de bloques."
                        ((num_err++))
                    fi
                done

                if [[ $num_err -gt 0 ]]; then
                    exit 1
                fi
            else
                msgError "Lista de dispositivos que van a formar el grupo erronea: $linea"
                exit 1
            fi
        elif [[ $n_linea -gt 2 ]]; then
            if [[ $linea =~ ^[\ \t]*([a-zA-Z0-9]*)[\ \t]*([0-9]*[EPTGMK]B)[\ \t]*$ ]]; then
                volumenes+=(${BASH_REMATCH[1]} ${BASH_REMATCH[2]})
            else
                msgError "Error en el formato de volumen lógico: $linea"
            fi
        fi
    fi
done < ${0/.sh/.conf}

instalarPaquete lvm2

msgEstado "Inicializando volumenes..."
pvcreate $lista_dispositivos
if [[ $? -ne 0 ]]; then
    msgError "Error de creacion de volumenes."
    exit 1
fi

msgEstado "Creando grupo '${nombre}'..."
vgcreate $nombre $lista_dispositivos
if [[ $? -ne 0 ]]; then
    msgError "Se ha producido un error creando el grupo."
    exit 1
fi

num_vols=$((${#volumenes[@]} / 2))
for ((i=0; i < $num_vols; i++)); do
    vNombre=${volumenes[$((i*2))]}
    vTam=${volumenes[$((i*2 + 1))]}

    msgEstado "Creando volumen lógico '${vNombre}' de tamaño '${vTam}'..."
    lvcreate $nombre --name $vNombre --size $vTam
    if [[ $? -ne 0 ]]; then
        msgError "Se ha producido un error al crear el volumen."
        exit 1
    fi

    msgEstado "Formateando '/dev/${nombre}/${vNombre}' como ext4..."
    mkfs.ext4 /dev/${nombre}/${vNombre}
    if [[ $? -ne 0 ]]; then
        msgError "Se ha producido un error al formatear el volumen."
        exit 1
    fi
done
