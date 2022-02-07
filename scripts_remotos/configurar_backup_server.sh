#!/bin/bash
#
# Script de configuración del servicio backup_server.
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
                dir_backup=${BASH_REMATCH[1]}
            else
                msgError "Directorio de backup erroneo: $linea"
                exit 1
            fi
        fi
    fi
done < ${0/.sh/.conf}

instalarPaquete rsync

msgEstado "Creando usuario de backups con directorio '${dir_backup}'..."
adduser --disabled-password --gecos "Backups" --home $dir_backup backupsrv
if [[ $? -ne 0 ]]; then
    echo "Error al crear el usuario de backups."
    exit 1
fi

msgEstado "Creando key de backups..."
su - backupsrv -c "ssh-keygen -t rsa -f ~/.ssh/id_rsa"
if [[ $? -ne 0 ]]; then
    echo "Error al crear el par de claves de backups."
    exit 1
fi

msgEstado "Configurando rrsync..."

su - backupsrv -c "mkdir ~/bin && zcat /usr/share/doc/rsync/scripts/rrsync.gz > ~/bin/rrsync && chmod +x ~/bin/rrsync"
if [[ $? -ne 0 ]]; then
    echo "Error al instalar rrsync."
    exit 1
fi

echo -n 'command="$HOME/bin/rrsync $HOME",no-agent-forwarding,no-port-forwarding,no-pty,no-user-rc,no-X11-forwarding ' | su - backupsrv -c "cat > ~/.ssh/authorized_keys && cat ~/.ssh/id_rsa.pub >> ~/.ssh/authorized_keys"
if [[ $? -ne 0 ]]; then
    echo "Error al autorizar el par de claves."
    exit 1
fi
