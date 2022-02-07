#!/bin/bash
#
# Script de configuración del servicio nfs_client.
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
        if [[ $linea =~ ^[\ \t]*([a-zA-Z0-9_\.\-]*)[:]*(/[a-zA-Z0-9/_\.\-]*)[\ \t]*(/[a-zA-Z0-9/_\.\-]*)[\ \t]*$ ]]; then
            exports+=(${BASH_REMATCH[1]} ${BASH_REMATCH[2]} ${BASH_REMATCH[3]})
        else
            msgError "Formato incorrecto: $linea"
            exit 1
        fi
    fi
done < ${0/.sh/.conf}

if [[ $num_err -gt 0 ]]; then
    exit 1
fi

instalarPaquete nfs-common

num_err=0
num_exports=$((${#exports[@]} / 3))
for ((i < 0; i < $num_exports; i++)); do
    eHost=${exports[$((i*3))]}
    ePath=${exports[$((i*3 + 1))]}
    eMount=${exports[$((i*3 + 2))]}

    msgEstado "Creando punto de montaje '${eMount}'..."
    mkdir -p ${eMount}

    if [[ $? -ne 0 ]]; then
        msgError "No se ha podido crear el punto de montaje."
        ((num_err++))
    else
        msgEstado "Montando el export '${eHost}:${ePath}'..."
        mount -t nfs ${eHost}:${ePath} ${eMount}

        if [[ $? -ne 0 ]]; then
            msgError "No se ha podido montar el export."
            ((num_err++))

        else
            msgEstado "Configurando el automontaje de '${eHost}:${ePath}' en '${eMount}'..."

            if [[ ! `grep ${eHost}:${ePath} /etc/fstab 2> /dev/null | grep -vP "^[ \t]*#" 2> /dev/null` =~ ^$ ]]; then
                msgError "El export ya se encuentra en /etc/fstab"
                ((num_err++))

            else
                echo -e "${eHost}:${ePath}\t${eMount}\tnfs\trw,sync,hard,intr\t0\t0" >> /etc/fstab

                if [[ $? -ne 0 ]]; then
                    msgError "No se ha podido configurar el automontaje."
                    ((num_err++))
                fi
            fi
        fi
    fi
done

if [[ $num_err -gt 0 ]]; then
    exit 1
fi
