#!/bin/bash
#
# Script de configuración del servicio raid.
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
            if [[ $linea =~ ^[\ \t]*(/dev/[a-zA-Z0-9/_\.\-]*)[\ \t]*$ ]]; then
                dispositivo=${BASH_REMATCH[1]}
                if [[ -e $dispositivo ]]; then
                    msgError "El dispositivo '$dispositivo' ya existe."
                    exit 1
                fi
            else
                msgError "Nombre del dispositivo raid erroneo: $linea"
                exit 1
            fi
        elif [[ $n_linea -eq 2 ]]; then
            if [[ $linea =~ ^[\ \t]*([0-9]*)*[\ \t]*$ ]]; then
                nivel_raid=${BASH_REMATCH[1]}
            else
                msgError "Nivel de raid erroneo: $linea"
                exit 1
            fi
        elif [[ $n_linea -eq 3 ]]; then
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
                msgError "Lista de dispositivos que van a formar el raid erronea: $linea"
                exit 1
            fi
        fi
    fi
done < ${0/.sh/.conf}

instalarPaquete mdadm

msgEstado "Configurando raid:"
msgEstado "\tRaid: $dispositivo"
msgEstado "\tNivel: $nivel_raid"
msgEstado "\tDispositivos ($num_dispositivos): $lista_dispositivos"

yes | mdadm --create $dispositivo --level=$nivel_raid --raid-devices=$num_dispositivos $lista_dispositivos
if [[ $? -ne 0 ]]; then
    msgError "Error creando el raid."
    exit 1
fi

msgEstado "Formateando '$dispositivo' en ext4..."

mkfs.ext4 $dispositivo
if [[ $? -ne 0 ]]; then
    msgError "Error creando el raid."
    exit 1
fi
