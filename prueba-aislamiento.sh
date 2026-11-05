#!/bin/bash
# Lanza un contenedor temporal en la red del honeypot y comprueba que no llega
# a ninguno de PRUEBA_DESTINOS. Sale con error si alguno responde.
set -euo pipefail

ENV_FILE=${ENV_FILE:-/opt/honeypot/.env}
# shellcheck source=/dev/null
[ -f "$ENV_FILE" ] && . "$ENV_FILE"
DESTINOS=${PRUEBA_DESTINOS:?"define PRUEBA_DESTINOS en $ENV_FILE"}

# shellcheck disable=SC2016  # las variables se expanden dentro del contenedor
docker run --rm --network honeypot -e DESTINOS="$DESTINOS" alpine:3.20 sh -c '
  fail=0
  for t in $DESTINOS; do
    if nc -z -w 3 "${t%:*}" "${t#*:}" 2>/dev/null; then
      echo "  ✗ llega a $t"; fail=1
    else
      echo "  ✓ sin acceso a $t"
    fi
  done
  if wget -q -T 8 -O /dev/null http://example.com; then
    echo "  ✓ sale a internet"
  else
    echo "  · sin salida a internet (no es grave)"
  fi
  exit $fail'
