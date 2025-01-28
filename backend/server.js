require('dotenv').config({ path: '../.env' });
const express = require('express');
const cors = require('cors');
const dotenv = require('dotenv');
const { MercadoPagoConfig, Payment, Preference } = require('mercadopago');
const stripe = require('stripe')(process.env.STRIPE_SECRET_KEY);

const app = express();
const port = process.env.PORT || 3000;

app.use(cors());
app.use(express.json());

// Configurar Mercado Pago
const client = new MercadoPagoConfig({ 
  accessToken: 'TEST-7227506708239646-041000-47b9e4c0a6c3329f5f6efbd6057d17d1-185810645',
});

const payment = new Payment(client);
const preference = new Preference(client);

// Rota para criar PaymentIntent
app.post('/create-payment-intent', async (req, res) => {
  try {
    const { amount, currency } = req.body;

    // Criar ou recuperar cliente
    const customer = await stripe.customers.create();

    // Criar chave efêmera
    const ephemeralKey = await stripe.ephemeralKeys.create(
      { customer: customer.id },
      { apiVersion: '2023-10-16' }
    );

    // Criar PaymentIntent
    const paymentIntent = await stripe.paymentIntents.create({
      amount,
      currency,
      customer: customer.id,
      automatic_payment_methods: {
        enabled: true,
        allow_redirects: 'always',
      },
    });

    res.json({
      clientSecret: paymentIntent.client_secret,
      ephemeralKey: ephemeralKey.secret,
      customer: customer.id,
    });
  } catch (error) {
    res.status(500).json({ error: error.message });
  }
});

// Rota para criar preferência do Mercado Pago
app.post('/create-mercadopago-preference', async (req, res) => {
  try {
    const { amount, currency } = req.body;

    const preferenceData = {
      items: [
        {
          title: 'Doação para Beats Monitor',
          unit_price: Number(amount),
          quantity: 1,
        },
      ],
      back_urls: {
        success: 'http://localhost:3000/success',
        failure: 'http://localhost:3000/failure',
        pending: 'http://localhost:3000/pending',
      },
      auto_return: 'approved',
      notification_url: 'http://localhost:3000/mercadopago-webhook',
    };

    const response = await preference.create({ body: preferenceData });

    res.json({ 
      preferenceId: response.id,
      checkoutUrl: response.init_point,
    });
  } catch (error) {
    console.error('Erro ao criar preferência:', error);
    res.status(500).json({ error: error.message });
  }
});

// Rota para verificar status do pagamento
app.get('/mercadopago-status/:paymentId', async (req, res) => {
  try {
    const response = await payment.get({ id: req.params.paymentId });
    res.json({ status: response.status });
  } catch (error) {
    console.error('Erro ao verificar status:', error);
    res.status(500).json({ error: error.message });
  }
});

// Webhook do Mercado Pago
app.post('/mercadopago-webhook', async (req, res) => {
  try {
    const { type, data } = req.body;
    
    if (type === 'payment') {
      const response = await payment.get({ id: data.id });
      console.log('Status do pagamento:', response.status);
      
      // Aqui você pode atualizar seu banco de dados ou enviar notificações
    }
    
    res.sendStatus(200);
  } catch (error) {
    console.error('Erro no webhook:', error);
    res.status(500).json({ error: error.message });
  }
});

// Endpoint para processar pagamento
app.post('/process-payment', async (req, res) => {
  try {
    const { payment_method, payment_data, amount, currency } = req.body;

    let paymentResponse;
    if (payment_method === 'credit_card') {
      // Processar pagamento com cartão
      const paymentData = {
        transaction_amount: Number(amount),
        token: payment_data.token,
        description: "Doação para Beats Monitor",
        installments: payment_data.installments || 1,
        payment_method_id: payment_data.payment_method_id,
        payer: {
          email: payment_data.email || "test@test.com",
        },
      };

      paymentResponse = await payment.create({ body: paymentData });

      return res.json({
        status: paymentResponse.status,
        status_detail: paymentResponse.status_detail,
        id: paymentResponse.id,
      });

    } else if (payment_method === 'pix') {
      // Gerar pagamento PIX
      const paymentData = {
        transaction_amount: Number(amount),
        description: "Doação para Beats Monitor",
        payment_method_id: "pix",
        payer: {
          email: payment_data.email || "test@test.com",
          first_name: "Test",
          last_name: "User",
          identification: {
            type: "CPF",
            number: "19119119100"
          },
        },
      };

      paymentResponse = await payment.create({ body: paymentData });

      const qrCode = paymentResponse.point_of_interaction.transaction_data.qr_code;
      const qrCodeBase64 = paymentResponse.point_of_interaction.transaction_data.qr_code_base64;

      return res.json({
        status: paymentResponse.status,
        status_detail: paymentResponse.status_detail,
        id: paymentResponse.id,
        pix_qr_code: qrCode,
        pix_qr_code_base64: qrCodeBase64,
      });
    }

    throw new Error('Método de pagamento não suportado');
  } catch (error) {
    console.error('Erro ao processar pagamento:', error);
    res.status(500).json({
      error: 'Erro ao processar pagamento',
      details: error.message
    });
  }
});

// Rota de teste
app.get('/health', (req, res) => {
  res.json({ status: 'OK' });
});

app.listen(port, () => {
  console.log(`Servidor rodando na porta ${port}`);
});
