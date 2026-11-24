# Atividade individual 1 · Serverless — Guia de transporte do Rota Vital

**Aluna:** Gabriela Bayo de Barros Russell · Infraestrutura de Software · ADS · CESAR School · 2026.2

Função serverless em Python 3.12 que recebe uma requisição do Rota Vital e devolve a guia de transporte. Ela é acionada por evento (`sam local invoke`) e por HTTP (`POST /guias` com `sam local start-api`).

**Caminho escolhido:** Caminho A, com AWS SAM CLI local (sem conta AWS).

## Estrutura

```
.
├── template.yaml            # SAM: função, rota POST /guias, Timeout em Globals
├── hello_world/app.py       # handler (código do Passo 2)
├── events/pedido.json       # evento API Gateway (Passo 3)
├── events/pedido-demorado.json
├── rodar_experimentos.sh    # roda os Passos 3, 4 e 5 e salva as saídas
└── evidencias/              # prints das execuções
```

## Pré-requisitos

- Docker Desktop aberto
- AWS SAM CLI (`sam --version`)
- Python 3.12
- No Windows, use o Git Bash ou o WSL

> **Observação (Windows):** no meu computador, o Git Bash só reconheceu o SAM como `sam.cmd`, e o Python local era 3.11. Por isso rodei `sam.cmd build --use-container`, que faz a build dentro de um container com Python 3.12. Nos comandos abaixo, quem estiver no Windows pode trocar `sam` por `sam.cmd`.

## Como rodar

O projeto foi criado com `sam init` (AWS Quick Start Templates → Hello World Example → Python 3.12 → zip). No `template.yaml`, troquei a rota `/hello` (GET) por `/guias` (POST) e o `app.py` pelo código do enunciado.

### Passo 3: invocar com evento

```bash
sam local generate-event apigateway aws-proxy --method POST --path guias \
  --body '{"requisicaoId":"R-001","hospital":"H-Recife","bolsas":["O-NEG-0142"]}' > events/pedido.json
sam build
sam local invoke -e events/pedido.json   # rodar 2 vezes e anotar o tempo
```

### Passo 4: acionar por HTTP

```bash
sam local start-api
# em outro terminal, 3 vezes:
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
  -d '{"requisicaoId":"R-002","hospital":"H-Caruaru"}'
```

Depois, pare o servidor (Ctrl+C) e repita com `sam local start-api --warm-containers LAZY`.

### Passo 5: limite de tempo

```bash
curl -X POST http://127.0.0.1:3000/guias -H "Content-Type: application/json" \
  -d '{"requisicaoId":"R-003","demorar":true}'
```

Depois, troque `Timeout: 3` por `Timeout: 10` em `Globals` no `template.yaml`, rode `sam build` e repita.

### Atalho

`./rodar_experimentos.sh` executa os Passos 3, 4 e 5 em sequência e grava as saídas em `evidencias/`.

## Resultados

| Experimento | Resultado |
|---|---|
| `sam local invoke` – 1ª vez | 16,0 s no total · Duration 166 ms |
| `sam local invoke` – 2ª vez | 10,6 s no total · Duration 86 ms |
| `start-api` sem warm containers (3 curls) | `invocacaoNesteAmbiente`: 1, 1, 1 |
| `start-api --warm-containers LAZY` (3 curls) | `invocacaoNesteAmbiente`: 2, 3, 4 (a chamada 1 foi um teste anterior no mesmo container) |
| `demorar=true` com Timeout 3 | `Function 'GuiaFunction' timed out after 3 seconds` · curl recebeu `Internal server error` (HTTP 502) |
| `demorar=true` com Timeout 10 | HTTP 201 depois de ~5 s, guia `G-R-003` |

Os prints de cada passo estão em `evidencias/`.

## Respostas

**1. Por que a primeira invocação demorou mais que a segunda? O que acontece na fase de Init?**

No meu teste, a primeira levou 16,0 s (Duration 166 ms) e a segunda 10,6 s (Duration 86 ms). A primeira foi um *cold start*. Antes de executar o handler, a plataforma precisa preparar o ambiente: baixar o código, subir o container (no SAM local, o Docker cria o container a partir da imagem do runtime) e iniciar o Python. Depois disso vem a fase de Init, que roda tudo o que está fora do handler (os imports e a variável global `contador = 0`). Na segunda vez, a imagem e as camadas já estavam em cache, por isso o tempo caiu. No Lambda de verdade, se o ambiente ainda estiver "quente", o Init nem acontece, e só o handler roda (*warm start*).

**2. O que o campo `invocacaoNesteAmbiente` mostrou com e sem `--warm-containers`? O que isso diz sobre guardar estado numa variável global?**

Sem a flag, o SAM cria um container novo para cada chamada, então o contador voltou sempre para 1. Com `--warm-containers LAZY`, o container é reaproveitado e o contador continuou subindo (no meu teste deu 2, 3, 4, porque uma chamada anterior já tinha usado o mesmo container). Isso mostra que a variável global só "lembra" de algo enquanto o mesmo ambiente estiver vivo. Na nuvem, a plataforma pode destruir esse ambiente ou criar vários em paralelo a qualquer momento. Então não dá para confiar em estado guardado na função. O certo é guardar em um serviço externo (banco de dados, cache, S3). A global serve para reaproveitar coisas caras de criar, como conexões e clientes.

**3. O que aconteceu com `demorar = true`? Qual é o tempo máximo de uma execução no Lambda, e o que fazer com um trabalho mais longo?**

Com Timeout 3, a função ia dormir 5 s, mas foi interrompida aos 3 s. O SAM registrou *"Function 'GuiaFunction' timed out after 3 seconds"*, e o curl recebeu `Internal server error` (HTTP 502) em vez da guia. Com Timeout 10, a chamada terminou normalmente em cerca de 5 s e retornou a guia `G-R-003`. No Lambda, o máximo é **15 minutos (900 s)**. Para trabalhos mais longos, dá para dividir o trabalho em etapas menores orquestradas (Step Functions), processar de forma assíncrona com uma fila (SQS) ou usar containers/servidores sem esse limite (ECS/Fargate, EC2).

**4. Quanto custa 1 milhão de execuções com 128 MB e 100 ms?**

- Requisições: 1.000.000 × US$ 0,20 / 1.000.000 = **US$ 0,20**
- Memória: 128 MB = 0,125 GB
- GB-s por execução: 0,125 GB × 0,1 s = 0,0125 GB-s
- GB-s total: 0,0125 × 1.000.000 = 12.500 GB-s
- Computação: 12.500 × US$ 0,0000166667 = **US$ 0,2083**
- **Total ≈ US$ 0,41** por milhão de execuções (sem contar a faixa gratuita, que cobriria tudo isso)

**5. Em que parte do Rota Vital uma função assim faria sentido, e em qual não faria?**

Faz sentido em tarefas curtas e disparadas por evento, como esta: gerar a guia de transporte quando uma requisição de bolsa é aprovada, enviar notificações ao hospital ou validar um pedido. São tarefas rápidas e sem estado, e o volume varia, então pagar só pelo uso compensa. Não faz sentido no que precisa de estado contínuo ou de processamento longo, como o acompanhamento em tempo real do transporte (conexões abertas, WebSocket, posição contínua) ou um processamento pesado e demorado que passaria de 15 minutos. Também não é uma boa escolha onde o cold start atrapalha uma resposta crítica que precisa ser instantânea.

## Uso de IA

- **Ferramenta:** Claude (Anthropic).
- **Finalidade:** organizar o projeto (template.yaml, script de execução) e me ajudar a estruturar o README e a revisar as respostas às perguntas.
- **Como validei:** rodei todos os passos no meu computador com SAM CLI e Docker, conferi as saídas (tempos, contador, erro de timeout) e ajustei as respostas e a tabela de resultados com o que observei. 
