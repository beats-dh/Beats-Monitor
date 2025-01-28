import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/mercadopago_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

class MercadoPagoPaymentScreen extends StatefulWidget {
  final double amount;
  final String description;

  const MercadoPagoPaymentScreen({
    super.key,
    required this.amount,
    required this.description,
  });

  @override
  State<MercadoPagoPaymentScreen> createState() => _MercadoPagoPaymentScreenState();
}

class _MercadoPagoPaymentScreenState extends State<MercadoPagoPaymentScreen> {
  String? _qrCode;
  final _formKey = GlobalKey<FormState>();
  String _selectedPaymentMethod = 'credit_card';
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _nameController = TextEditingController();
  final _cpfController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  String _cardType = '';

  @override
  void initState() {
    super.initState();
    // Preenche os campos com o cartão de teste
    if (mounted) {
      setState(() {
        _cardNumberController.text = '5031 4332 1540 6351';
        _expiryController.text = '11/25';
        _cvvController.text = '123';
        _nameController.text = 'APRO';
        _cpfController.text = '12345678909';
      });
    }
    // Identificar o tipo inicial do cartão
    _updateCardType(_cardNumberController.text);
  }

  void _updateCardType(String number) {
    setState(() {
      _cardType = MercadoPagoService.getCardType(number);
    });
  }

  @override
  void dispose() {
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _nameController.dispose();
    _cpfController.dispose();
    super.dispose();
  }

  String? _validateCardNumber(String? value) {
    if (value == null || value.isEmpty) {
      return 'Número do cartão é obrigatório';
    }
    if (value.replaceAll(' ', '').length != 16) {
      return 'Número do cartão inválido';
    }
    return null;
  }

  String? _validateExpiry(String? value) {
    if (value == null || value.isEmpty) {
      return 'Data de validade é obrigatória';
    }
    if (!RegExp(r'^\d{2}/\d{2}$').hasMatch(value)) {
      return 'Formato inválido (MM/YY)';
    }
    return null;
  }

  String? _validateCVV(String? value) {
    if (value == null || value.isEmpty) {
      return 'CVV é obrigatório';
    }
    if (value.length < 3 || value.length > 4) {
      return 'CVV inválido';
    }
    return null;
  }

  String? _validateName(String? value) {
    if (value == null || value.isEmpty) {
      return 'Nome é obrigatório';
    }
    return null;
  }

  String? _validateCPF(String? value) {
    if (value == null || value.isEmpty) {
      return 'CPF é obrigatório';
    }
    if (value.length != 11) {
      return 'CPF inválido';
    }
    return null;
  }

  Future<void> _processPayment() async {
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final response = await MercadoPagoService.processPayment(
        context: context,
        cardData: {
          'number': _cardNumberController.text,
          'cvv': _cvvController.text,
          'expiry': _expiryController.text,
          'name': _nameController.text,
          'cpf': _cpfController.text,
        },
        amount: widget.amount,
        description: widget.description,
        paymentMethod: _selectedPaymentMethod,
      );

      if (!mounted) return;

      if (response != null && response['status'] == 'approved') {
        // Apenas mostrar snackbar de sucesso
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pagamento realizado com sucesso!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'Erro ao processar pagamento';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pagamento'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(false),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Valor da doação
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Text(
                      'Valor da doação',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'R\$ ${widget.amount.toStringAsFixed(2)}',
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Seleção do método de pagamento
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Método de pagamento',
                      style: TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(
                          value: 'credit_card',
                          label: Text('Cartão de Crédito'),
                          icon: Icon(Icons.credit_card),
                        ),
                        ButtonSegment(
                          value: 'pix',
                          label: Text('PIX'),
                          icon: Icon(Icons.qr_code),
                        ),
                      ],
                      selected: {_selectedPaymentMethod},
                      onSelectionChanged: (Set<String> selection) {
                        setState(() {
                          _selectedPaymentMethod = selection.first;
                          _errorMessage = null;
                          _qrCode = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Cartão de teste
            if (_selectedPaymentMethod == 'credit_card')
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        'Cartão de Teste:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text('Número: 5031 4332 1540 6351'),
                      Text('CVV: 123'),
                      Text('Data: 11/25'),
                      Text('Nome: APRO'),
                      Text('CPF: 12345678909'),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Formulário de cartão de crédito
            if (_selectedPaymentMethod == 'credit_card')
              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _cardNumberController,
                      decoration: InputDecoration(
                        labelText: 'Número do Cartão',
                        prefixIcon: const Icon(Icons.credit_card),
                        suffixText: _cardType.toUpperCase(),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        _CardNumberFormatter(),
                      ],
                      validator: _validateCardNumber,
                      onChanged: (value) {
                        _updateCardType(value);
                      },
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _expiryController,
                            decoration: const InputDecoration(
                              labelText: 'Validade (MM/YY)',
                              prefixIcon: Icon(Icons.calendar_today),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              _ExpiryFormatter(),
                            ],
                            validator: _validateExpiry,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: TextFormField(
                            controller: _cvvController,
                            decoration: const InputDecoration(
                              labelText: 'CVV',
                              prefixIcon: Icon(Icons.security),
                            ),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(4),
                            ],
                            validator: _validateCVV,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _nameController,
                      decoration: const InputDecoration(
                        labelText: 'Nome no Cartão',
                        prefixIcon: Icon(Icons.person),
                      ),
                      textCapitalization: TextCapitalization.words,
                      validator: _validateName,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _cpfController,
                      decoration: const InputDecoration(
                        labelText: 'CPF',
                        prefixIcon: Icon(Icons.badge),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(11),
                      ],
                      validator: _validateCPF,
                    ),
                  ],
                ),
              ),

            // QR Code do PIX
            if (_selectedPaymentMethod == 'pix' && _qrCode != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      const Text(
                        'QR Code PIX',
                        style: TextStyle(fontSize: 16),
                      ),
                      const SizedBox(height: 16),
                      QrImageView(
                        data: _qrCode!,
                        version: QrVersions.auto,
                        size: 200.0,
                      ),
                      const SizedBox(height: 16),
                      OutlinedButton.icon(
                        onPressed: () {
                          if (_qrCode != null) {
                            Clipboard.setData(ClipboardData(text: _qrCode!));
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Código PIX copiado!'),
                              ),
                            );
                          }
                        },
                        icon: const Icon(Icons.copy),
                        label: const Text('Copiar código PIX'),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Mensagem de erro
            if (_errorMessage != null)
              Card(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: Theme.of(context).colorScheme.error,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            const SizedBox(height: 16),

            // Botão de pagamento
            FilledButton.icon(
              onPressed: _isLoading ? null : _processPayment,
              icon: _isLoading
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(),
                    )
                  : const Icon(Icons.payment),
              label: Text(_selectedPaymentMethod == 'credit_card'
                  ? 'Pagar com Cartão'
                  : 'Gerar QR Code PIX'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String numbers = newValue.text.replaceAll(' ', '');
    String formatted = '';

    for (int i = 0; i < numbers.length; i++) {
      if (i > 0 && i % 4 == 0) {
        formatted += ' ';
      }
      formatted += numbers[i];
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}

class _ExpiryFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    String numbers = newValue.text.replaceAll('/', '');
    if (numbers.length > 4) {
      numbers = numbers.substring(0, 4);
    }

    String formatted = '';
    if (numbers.length >= 2) {
      formatted = '${numbers.substring(0, 2)}/${numbers.substring(2)}';
    } else {
      formatted = numbers;
    }

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
