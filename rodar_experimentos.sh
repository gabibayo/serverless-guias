#!/usr/bin/env bash
sam() { sam.cmd "$@"; }
# Roda os Passos 3, 4 e 5 e salva as saídas em evidencias/*.txt
# Uso: ./rodar_experimentos.sh   (Docker precisa estar aberto)
# No Windows: rodar no Git Bash ou WSL.
set -u
mkdir -p evidencias
PEDIDO='{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
DEMORADO='{"requisicaoId":"R-003","demorar":true}'

esperar_api() {  # espera o start-api responder
  for i in $(seq 1 60); do
    curl -s -o /dev/null http://127.0.0.1:3000/guias -X POST -d '{}' && return 0
    sleep 1
  done
  echo "start-api não subiu"; return 1
}

chamar() {  # $1 = body
  curl -s -w "  [HTTP %{http_code} | %{time_total}s]\n" -X POST http://127.0.0.1:3000/guias \
       -H "Content-Type: application/json" -d "$1"
}

echo "== sam --version ==" | tee evidencias/00-versoes.txt
{ sam --version; docker --version; python3 --version; } 2>&1 | tee -a evidencias/00-versoes.txt

echo "== Passo 3: build e duas invocações com evento ==" | tee evidencias/03-invoke.txt
sam build --use-container 2>&1 | tee -a evidencias/03-invoke.txt
for n in 1 2; do
  echo "--- Invocação $n ---" | tee -a evidencias/03-invoke.txt
  { time sam local invoke -e events/pedido.json ; } 2>&1 | tee -a evidencias/03-invoke.txt
done

echo "== Passo 4a: start-api SEM warm containers ==" | tee evidencias/04-http.txt
sam local start-api > evidencias/04a-start-api.log 2>&1 &
PID=$!; esperar_api
for n in 1 2 3; do chamar "$PEDIDO" | tee -a evidencias/04-http.txt; done
kill $PID; wait $PID 2>/dev/null

echo "== Passo 4b: start-api COM --warm-containers LAZY ==" | tee -a evidencias/04-http.txt
sam local start-api --warm-containers LAZY > evidencias/04b-start-api-lazy.log 2>&1 &
PID=$!; esperar_api
for n in 1 2 3; do chamar "$PEDIDO" | tee -a evidencias/04-http.txt; done
kill $PID; wait $PID 2>/dev/null

echo "== Passo 5: demorar=true com Timeout 3 ==" | tee evidencias/05-timeout.txt
sam local start-api > evidencias/05a-start-api.log 2>&1 &
PID=$!; esperar_api
chamar "$DEMORADO" | tee -a evidencias/05-timeout.txt
kill $PID; wait $PID 2>/dev/null
grep -i "timed out" evidencias/05a-start-api.log | tee -a evidencias/05-timeout.txt

echo "== Passo 5: Timeout 10 ==" | tee -a evidencias/05-timeout.txt
cp template.yaml template.yaml.bak
sed -i.tmp 's/Timeout: 3 /Timeout: 10/' template.yaml && rm -f template.yaml.tmp
sam build --use-container >/dev/null 2>&1
sam local start-api > evidencias/05b-start-api.log 2>&1 &
PID=$!; esperar_api
chamar "$DEMORADO" | tee -a evidencias/05-timeout.txt
kill $PID; wait $PID 2>/dev/null
mv template.yaml.bak template.yaml   # volta o template para Timeout 3

echo; echo "Pronto. Saídas em evidencias/. Agora tire os prints do terminal."
