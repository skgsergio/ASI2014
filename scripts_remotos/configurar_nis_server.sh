#!/bin/bash
#
# Script de configuración del servicio nis_server.
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

msgEstado "Configurando el servidor nis..."
sed -i 's#NISSERVER=.*#NISSERVER=master#' /etc/default/nis
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido configurar nis como servidor."
    exit 1
fi
sed -i 's#NISCLIENT=.*#NISCLIENT=false#' /etc/default/nis
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido desactivar la opcion de cliente nis."
    exit 1
fi

echo "ypserver localhost" >> /etc/yp.conf
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido añadir el servidor en '/etc/yp.conf'."
    exit 1
fi

echo "${dominio}" > /etc/defaultdomain
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido configurar el domino."
    exit 1
fi

msgEstado "Arrancando el servidor nis..."
service nis restart
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido reiniciar el demonio."
    exit 1
fi

msgEstado "Inicializando el servidor nis..."
echo -n | /usr/lib/yp/ypinit -m
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido inicializar el servidor."
    exit 1
fi

msgEstado "Reiniciando el servidor nis..."
service nis restart
if [[ $? -ne 0 ]]; then
    msgError "No se ha podido reiniciar el demonio."
    exit 1
fi
