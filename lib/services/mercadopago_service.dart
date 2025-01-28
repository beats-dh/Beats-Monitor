import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:logger/logger.dart';

class MercadoPagoService {
  static const String _publicKey = 'TEST-9d6b1596-e0b5-4d86-9f9f-dafccb262892';
  static const String _accessToken = 'TEST-7227506708239646-041000-47b9e4c0a6c3329f5f6efbd6057d17d1-185810645';
  static final _logger = Logger();

  // Função para identificar o tipo do cartão baseado nos primeiros dígitos
  static String getCardType(String cardNumber) {
    // Remove espaços e traços
    cardNumber = cardNumber.replaceAll(RegExp(r'[\s-]'), '');
    
    // Mastercard
    if (RegExp(r'^5[1-5]').hasMatch(cardNumber)) {
      return 'master';
    }
    // Visa
    else if (RegExp(r'^4').hasMatch(cardNumber)) {
      return 'visa';
    }
    // American Express
    else if (RegExp(r'^3[47]').hasMatch(cardNumber)) {
      return 'amex';
    }
    // Diners Club
    else if (RegExp(r'^3(?:0[0-5]|[68])').hasMatch(cardNumber)) {
      return 'diners';
    }
    // Discover
    else if (RegExp(r'^6(?:011|5)').hasMatch(cardNumber)) {
      return 'discover';
    }
    // Elo
    else if (RegExp(r'^(636368|438935|504175|451416|636297|5067|4576|4011|506699)').hasMatch(cardNumber)) {
      return 'elo';
    }
    // Hipercard
    else if (RegExp(r'^(606282|3841)').hasMatch(cardNumber)) {
      return 'hipercard';
    }
    
    // Padrão para Mastercard se não identificar
    return 'master';
  }

  static Future<Map<String, dynamic>?> processPayment({
    required BuildContext context,
    required Map<String, String> cardData,
    required double amount,
    required String description,
    required String paymentMethod,
  }) async {
    try {
      if (paymentMethod == 'credit_card') {
        // Identificar o tipo do cartão
        final cardType = getCardType(cardData['number'] ?? '');
        
        // Criar token do cartão
        final cardToken = await _createCardToken(
          cardNumber: cardData['number'] ?? '',
          cvv: cardData['cvv'] ?? '',
          expiry: cardData['expiry'] ?? '',
          name: cardData['name'] ?? '',
          cpf: cardData['cpf'] ?? '',
        );

        _logger.d('Card Token: $cardToken');
        if (cardToken == null) {
          throw Exception('Erro ao gerar token do cartão');
        }

        // Criar pagamento com o token
        final response = await http.post(
          Uri.parse('https://api.mercadopago.com/v1/payments'),
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'transaction_amount': amount,
            'token': cardToken['id'],
            'description': description,
            'installments': 1,
            'payment_method_id': cardType,
            'payer': {
              'email': 'test@email.com',
              'identification': {
                'type': 'CPF',
                'number': cardData['cpf'],
              },
            },
          }),
        );

        _logger.d('Payment Response: ${response.body}');
        final responseData = jsonDecode(response.body);

        if (response.statusCode == 201) {
          return responseData;
        } else {
          String errorMessage = 'Erro ao processar pagamento';
          
          if (responseData['status'] == 'rejected') {
            switch (responseData['status_detail']) {
              case 'cc_rejected_high_risk':
                errorMessage = 'Pagamento rejeitado por suspeita de fraude';
                break;
              case 'cc_rejected_insufficient_amount':
                errorMessage = 'Saldo insuficiente';
                break;
              case 'cc_rejected_bad_filled_security_code':
                errorMessage = 'Código de segurança inválido';
                break;
              case 'cc_rejected_bad_filled_date':
                errorMessage = 'Data de validade incorreta';
                break;
              case 'cc_rejected_bad_filled_other':
                errorMessage = 'Cartão inválido';
                break;
            }
          }
          
          throw Exception(errorMessage);
        }
      } else if (paymentMethod == 'pix') {
        final response = await http.post(
          Uri.parse('https://api.mercadopago.com/v1/payments'),
          headers: {
            'Authorization': 'Bearer $_accessToken',
            'Content-Type': 'application/json',
          },
          body: jsonEncode({
            'transaction_amount': amount,
            'description': description,
            'payment_method_id': 'pix',
            'payer': {
              'email': 'test@email.com', // TODO: Pegar email do usuário
              'first_name': 'Test',
              'last_name': 'User',
              'identification': {
                'type': 'CPF',
                'number': '19119119100', // TODO: Pegar CPF do usuário
              },
            },
          }),
        );

        if (response.statusCode == 201) {
          final responseData = jsonDecode(response.body);
          return {
            'qr_code': responseData['point_of_interaction']['transaction_data']['qr_code'],
            'qr_code_base64': responseData['point_of_interaction']['transaction_data']['qr_code_base64'],
          };
        }

        throw Exception('Erro ao gerar QR code PIX');
      }

      throw Exception('Método de pagamento não suportado');
    } catch (e) {
      _logger.e('Erro ao processar pagamento: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro: $e')),
        );
      }
      return null;
    }
  }

  static Future<Map<String, dynamic>?> _createCardToken({
    required String cardNumber,
    required String cvv,
    required String expiry,
    required String name,
    required String cpf,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('https://api.mercadopago.com/v1/card_tokens?public_key=$_publicKey'),
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'card_number': cardNumber.replaceAll(' ', ''),
          'security_code': cvv,
          'expiration_month': int.parse(expiry.split('/')[0]),
          'expiration_year': int.parse('20${expiry.split('/')[1]}'),
          'cardholder': {
            'name': name,
            'identification': {
              'type': 'CPF',
              'number': cpf,
            },
          },
        }),
      );

      _logger.d('Card Token Response: ${response.body}');

      if (response.statusCode == 201) {
        return jsonDecode(response.body);
      }
      _logger.e('Erro ao gerar token: ${response.body}');
      return null;
    } catch (e) {
      _logger.e('Erro ao gerar token: $e');
      return null;
    }
  }
}
