import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'package:http/http.dart' as http;

class StripeService {
  static const String _baseUrl = 'http://177.23.187.59:3000'; // URL do backend local

  static Future<void> initialize() async {
    // Stripe já foi inicializado no main.dart
  }

  static Future<void> makePayment({
    required double amount,
    required String currency,
  }) async {
    // Verificar se está em uma plataforma suportada
    if (!Platform.isAndroid && !Platform.isIOS) {
      throw UnsupportedError(
        'Pagamentos com Stripe só estão disponíveis em dispositivos móveis.',
      );
    }

    try {
      // Criar PaymentIntent no backend
      final paymentIntent = await _createPaymentIntent(
        amount: (amount * 100).toInt(), // Stripe usa centavos
        currency: currency,
      );

      // Confirmar pagamento
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: paymentIntent['clientSecret'],
          merchantDisplayName: 'Beats Monitor',
          style: ThemeMode.system,
          primaryButtonLabel: 'Pagar',
          allowsDelayedPaymentMethods: true,
        ),
      );

      await Stripe.instance.presentPaymentSheet();
    } catch (e) {
      if (e is StripeException) {
        if (e.error.code == FailureCode.Canceled) {
          // Usuário cancelou o pagamento
          throw Exception('payment_canceled');
        }
      }
      throw Exception('Erro no pagamento: $e');
    }
  }

  static Future<Map<String, dynamic>> _createPaymentIntent({
    required int amount,
    required String currency,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('$_baseUrl/create-payment-intent'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'amount': amount,
          'currency': currency,
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Erro ao criar PaymentIntent: ${response.body}');
      }

      return json.decode(response.body);
    } catch (e) {
      throw Exception('Erro na comunicação com o backend: $e');
    }
  }
}
