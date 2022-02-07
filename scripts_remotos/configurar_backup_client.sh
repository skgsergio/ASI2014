#!/bin/bash
#
# Script de configuración del servicio backup_client.
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
            if [[ $linea =~ ^[\ \t]*(/[a-zA-Z0-9/_\.\-]*)[\ \t]*$ ]]; then
                directorio=${BASH_REMATCH[1]}
            else
                msgError "Directorio del que se va a realizar el backup erroneo: $linea"
                exit 1
            fi
        elif [[ $n_linea -eq 2 ]]; then
            if [[ $linea =~ ^[\ \t]*([a-zA-Z0-9_\.\-]*)[\ \t]*$ ]]; then
                servidor=${BASH_REMATCH[1]}
            else
                msgError "Servidor de backup erroneo: $linea"
                exit 1
            fi
        elif [[ $n_linea -eq 3 ]]; then
            if [[ $linea =~ ^[\ \t]*(/[a-zA-Z0-9/_\.\-]*)[\ \t]*$ ]]; then
                destino=${BASH_REMATCH[1]}
            else
                msgError "Destino del backup erroneo: $linea"
                exit 1
            fi
        elif [[ $n_linea -eq 4 ]]; then
            if [[ $linea =~ ^[\ \t]*([0-9]*)[\ \t]*$ ]]; then
                horas=${BASH_REMATCH[1]}
            else
                msgError "Periodicidad en horas erronea: $linea"
                exit 1
            fi
        fi
    fi
done < ${0/.sh/.conf}

instalarPaquete rsync

msgEstado "Creando directorio de configuraciones..."
mkdir /etc/autobackup/

msgEstado "Copiando identidad del servidor..."
home_backup=$(ssh -n -oLogLevel=ERROR -oConnectTimeout=1 -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no root@${servidor} "getent passwd backupsrv | cut -d: -f6")
if [[ $? -ne 0 ]]; then
    echo "Error al obtener el home del servidor."
    exit 1
fi

scp -oLogLevel=ERROR -oConnectTimeout=1 -oUserKnownHostsFile=/dev/null -oStrictHostKeyChecking=no root@${servidor}:${home_backup}/.ssh/id_rsa /etc/autobackup/id_rsa
if [[ $? -ne 0 ]]; then
    echo "Error al copiar la clave privada."
    exit 1
fi

msgEstado "Creando script de backup..."
echo '#!/bin/bash' > /etc/autobackup/script.sh
echo "rsync -e \"ssh -i /etc/autobackup/id_rsa\" -av ${directorio}/ backupsrv@${servidor}:${destino/$home_backup/}/" >> /etc/autobackup/script.sh

msgEstado "Cambiando permisos..."
chmod 700 /etc/autobackup/
chmod 600 /etc/autobackup/id_rsa
chmod 700 /etc/autobackup/script.sh

msgEstado "Programando tarea..."
echo "* */${horas} * * * root /etc/autobackup/script.sh" >> /etc/crontab
