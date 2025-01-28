import 'dart:io' show Platform;
import 'package:beats_monitor/screens/mercadopago_payment_screen.dart';
import 'package:beats_monitor/services/mercadopago_service.dart';
import 'package:flutter/material.dart';
import '../services/stripe_service.dart';
import '../widgets/donation_button.dart';

class DonationScreen extends StatefulWidget {
  const DonationScreen({Key? key}) : super(key: key);

  @override
  State<DonationScreen> createState() => _DonationScreenState();
}

class _DonationScreenState extends State<DonationScreen> {
  double? selectedAmount;
  bool isProcessing = false;
  final List<double> predefinedAmounts = [10.0, 25.0, 50.0, 100.0];
  final TextEditingController customAmountController = TextEditingController();
  String? _selectedPaymentMethod;

  Future<void> _processDonation() async {
    if (selectedAmount == null || selectedAmount! <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Por favor, selecione um valor para doar')),
      );
      return;
    }

    setState(() => isProcessing = true);

    try {
      // Mostrar diálogo para escolher o método de pagamento
      final paymentMethod = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Escolha o método de pagamento'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.credit_card, size: 32, color: Colors.blue),
                title: const Text('Cartão de Crédito (Stripe)'),
                onTap: () => Navigator.pop(context, 'stripe'),
              ),
              ListTile(
                leading: const Icon(Icons.payment, size: 32, color: Colors.lightBlue),
                title: const Text('Mercado Pago'),
                onTap: () => Navigator.pop(context, 'mercadopago'),
              ),
            ],
          ),
        ),
      );

      if (paymentMethod == null) {
        setState(() => isProcessing = false);
        return;
      }

      _selectedPaymentMethod = paymentMethod;

      if (_selectedPaymentMethod == 'stripe') {
        await StripeService.makePayment(
          amount: selectedAmount!,
          currency: 'brl',
        );
      } else if (_selectedPaymentMethod == 'mercadopago') {
        try {
          final success = await Navigator.of(context).push<bool>(
            MaterialPageRoute(
              builder: (context) => MercadoPagoPaymentScreen(
                amount: selectedAmount!,
                description: 'Doação para Beats Monitor',
              ),
            ),
          );

          if (success == true) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Doação realizada com sucesso!')),
            );
            Navigator.pop(context);
          }
        } catch (e) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Erro ao processar doação: $e')),
          );
        }
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Obrigado pela sua doação!'),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        if (e.toString().contains('payment_canceled')) {
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no pagamento: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isProcessing = false);
      }
    }
  }

  Future<bool> _onWillPop() async {
    if (isProcessing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aguarde o processamento do pagamento')),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Faça uma Doação'),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      children: [
                        Icon(
                          Icons.favorite,
                          color: Colors.red,
                          size: 48,
                        ),
                        SizedBox(height: 16),
                        Text(
                          'Apoie o Beats Monitor',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          'Sua doação ajuda a manter o projeto e desenvolver novas funcionalidades.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                if (!Platform.isAndroid && !Platform.isIOS) ...[
                  const Card(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Icon(
                            Icons.mobile_off,
                            color: Colors.grey,
                            size: 48,
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Pagamentos Indisponíveis',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            'Os pagamentos via Stripe estão disponíveis apenas em dispositivos móveis (Android e iOS).',
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 16),
                          ),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  const Text(
                    'Escolha um valor:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    alignment: WrapAlignment.center,
                    children: predefinedAmounts
                        .map(
                          (amount) => DonationButton(
                            amount: amount,
                            isSelected: selectedAmount == amount,
                            onPressed: () {
                              setState(() {
                                selectedAmount = amount;
                                customAmountController.clear();
                              });
                            },
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Ou digite um valor personalizado:',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: customAmountController,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: const InputDecoration(
                      prefixText: 'R\$ ',
                      border: OutlineInputBorder(),
                      hintText: '0,00',
                    ),
                    onChanged: (value) {
                      final amount = double.tryParse(
                        value.replaceAll(',', '.'),
                      );
                      setState(() {
                        selectedAmount = amount;
                      });
                    },
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: isProcessing ? null : _processDonation,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: isProcessing
                        ? const CircularProgressIndicator()
                        : const Text(
                            'Doar Agora',
                            style: TextStyle(fontSize: 18),
                          ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    customAmountController.dispose();
    super.dispose();
  }
}
