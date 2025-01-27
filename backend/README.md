# Backend do Beats Monitor

Este é o servidor backend responsável por processar pagamentos via Stripe para o Beats Monitor.

## Configuração

1. Instale as dependências:
```bash
npm install
```

2. O arquivo `.env` na raiz do projeto já contém as chaves necessárias do Stripe.

## Executando o servidor

Para desenvolvimento (com hot-reload):
```bash
npm run dev
```

Para produção:
```bash
npm start
```

O servidor estará rodando em `http://localhost:3000`.

## Endpoints

### POST /create-payment-intent
Cria um PaymentIntent do Stripe para processar um pagamento.

Payload:
```json
{
  "amount": 1000,    // valor em centavos
  "currency": "brl"  // código da moeda
}
```

Resposta:
```json
{
  "clientSecret": "pi_..."  // client secret do PaymentIntent
}
```

### GET /health
Endpoint de teste para verificar se o servidor está funcionando.

Resposta:
```json
{
  "status": "OK"
}
```
