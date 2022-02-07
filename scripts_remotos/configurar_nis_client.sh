#!/bin/bash
#
# Script de configuración del servicio nis_client.
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
n_linea=0
while read linea; do
    if [[ ! $linea =~ ^$ ]] && [[ ! $linea =~ ^[\ \t]*$ ]]; then
        ((n_linea++))
        if [[ $n_linea -eq 1 ]]; then
            if [[ $linea =~ ^[\ \t]*([a-zA-Z0-9_\.\-]*)[\ \t]*$ ]]; then
                dominio=${BASH_REMATCH[1]}
            else
                msgError "Formato incorrecto: $linea"
                exit 1
            fi
        elif [[ $n_linea -eq 2 ]]; then
            if [[ $linea =~ ^[\ \t]*([a-zA-Z0-9_\.\-]*)[\ \t]*$ ]]; then
                servidor=${BASH_REMATCH[1]}
            else
                msgError "Formato incorrecto: $linea"
                exit 1
            fi
        fi
    fi
done < ${0/.sh/.conf}

# Instalamos nis inhibiendo el inicio automatico del demonio
if [[ -f /usr/sbin/policy-rc.d ]]; then
    mv /usr/sbin/policy-rc.d /usr/sbin/policy-rc.d.bak
fi

cat <<EOF > /usr/sbin/policy-rc.d
#!/bin/sh
exit 101
EOF

chmod 755 /usr/sbin/policy-rc.d

instalarPaquete nis

rm -f /usr/sbin/policy-rc.d

if [[ -f /usr/sbin/policy-rc.d.bak ]]; then
    mv /usr/sbin/policy-rc.d.bak /usr/sbin/policy-rc.d
fi

msgEstado "Configurando el cliente nis..."
sed -i 's#NISSERVER=.*#NISSERVER=false#' /etc/default/nis
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido configurar nis como cliente."
    exit 1
fi
sed -i 's#NISCLIENT=.*#NISCLIENT=true#' /etc/default/nis
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido desactivar la opcion de cliente nis."
    exit 1
fi

echo "ypserver ${servidor}" >> /etc/yp.conf
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido añadir el servidor en '/etc/yp.conf'."
    exit 1
fi

echo "${dominio}" > /etc/defaultdomain
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido configurar el domino."
    exit 1
fi

msgEstado "Reiniciando el cliente nis..."
service nis restart
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido reiniciar el demonio."
    exit 1
fi

msgEstado "Configurando /etc/nsswitch.conf para usar nis..."
sed -i "s#\(passwd\|group\|shadow\):\([ \t]*\)\(.*\)#\1:\2nis \3#" /etc/nsswitch.conf
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido configurar '/etc/nsswitch.conf'."
    exit 1
fi
