import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/theka_provider.dart';
import '../providers/farm_provider.dart';
import '../models/models.dart';
import '../widgets/empty_state_widget.dart';
import 'theka_form_screen.dart';
import 'theka_details_screen.dart';

class ThekaListScreen extends StatefulWidget {
  const ThekaListScreen({super.key});

  @override
  State<ThekaListScreen> createState() => _ThekaListScreenState();
}

class _ThekaListScreenState extends State<ThekaListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ThekaProvider>().fetchThekas();
      context.read<FarmProvider>().fetchFarms();
    });
  }

  @override
  Widget build(BuildContext context) {
    final thekaProvider = Provider.of<ThekaProvider>(context);
    final farmProvider = Provider.of<FarmProvider>(context);
    final theme = Theme.of(context);

    // Calculate overall summaries
    double overallTotal = 0.0;
    double overallPaid = 0.0;

    for (var theka in thekaProvider.thekas) {
      overallTotal += theka.totalAmount;
      final insts = thekaProvider.getInstallmentsForTheka(theka.id!);
      for (var inst in insts) {
        overallPaid += inst.paidAmount;
      }
    }

    final double overallPending = overallTotal - overallPaid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('زمین کا ٹھیکہ (لیز ریکارڈ)'),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await thekaProvider.fetchThekas();
          await farmProvider.fetchFarms();
        },
        child: Column(
          children: [
            if (thekaProvider.thekas.isNotEmpty)
              _buildSummaryHeader(overallTotal, overallPaid, overallPending, theme),
            Expanded(
              child: thekaProvider.thekas.isEmpty
                  ? SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: SizedBox(
                        height: MediaQuery.of(context).size.height * 0.7,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const EmptyStateWidget(
                              message: 'کوئی ٹھیکہ معاہدہ موجود نہیں ہے',
                              subtitle: 'نیا ٹھیکہ معاہدہ درج کرنے کے لیے نیچے بٹن دبائیں',
                              fallbackIcon: Icons.description_outlined,
                              imageAsset: 'assets/images/wheat.png',
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(builder: (_) => const ThekaFormScreen()),
                                );
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('ٹھیکہ معاہدہ شامل کریں'),
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      itemCount: thekaProvider.thekas.length,
                      itemBuilder: (context, index) {
                        final theka = thekaProvider.thekas[index];
                        final farm = farmProvider.farms.firstWhere(
                          (f) => f.id == theka.farmId,
                          orElse: () => Farm(name: 'نامعلوم فارم', totalArea: 0.0, createdAt: ''),
                        );

                        // Find field name if applicable
                        String fieldText = '';
                        if (theka.fieldId != null) {
                          final fields = farmProvider.getFieldsForFarm(theka.farmId);
                          final field = fields.firstWhere(
                            (f) => f.id == theka.fieldId,
                            orElse: () => Field(farmId: elementsId(theka.farmId), name: '', sizeAcres: 0.0),
                          );
                          if (field.name.isNotEmpty) {
                            fieldText = ' - ${field.name}';
                          }
                        }

                        final insts = thekaProvider.getInstallmentsForTheka(theka.id!);
                        double paidAmt = 0.0;
                        int paidCount = 0;
                        for (var inst in insts) {
                          paidAmt += inst.paidAmount;
                          if (inst.status == 'Paid') {
                            paidCount++;
                          }
                        }
                        final double pendingAmt = theka.totalAmount - paidAmt;
                        final double progress = theka.totalAmount > 0 ? (paidAmt / theka.totalAmount) : 0.0;

                        // Urdu duration type mapping
                        String durationUrdu = theka.durationType;
                        if (theka.durationType == 'Yearly') {
                          durationUrdu = 'سالانہ';
                        } else if (theka.durationType == 'Seasonal') {
                          durationUrdu = 'موسمی / فصلاتی';
                        } else if (theka.durationType == 'Custom') {
                          durationUrdu = 'کسٹم';
                        }

                        return Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                          elevation: 3,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(16),
                            onTap: () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ThekaDetailsScreen(thekaId: theka.id!),
                                ),
                              );
                            },
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '${farm.name}$fieldText',
                                          style: const TextStyle(
                                            fontSize: 20,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: Colors.brown.shade50,
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: Colors.brown.shade200),
                                        ),
                                        child: Text(
                                          durationUrdu,
                                          style: TextStyle(
                                            color: Colors.brown.shade800,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (theka.durationDetails != null && theka.durationDetails!.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'تفصیل: ${theka.durationDetails}',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                                    ),
                                  ],
                                  const Divider(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      _buildAmountLabel('کل ٹھیکہ', theka.totalAmount, Colors.black),
                                      _buildAmountLabel('کل ادا شدہ', paidAmt, Colors.green),
                                      _buildAmountLabel('واجب الادا', pendingAmt, Colors.red.shade700),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: ClipRRect(
                                          borderRadius: BorderRadius.circular(10),
                                          child: LinearProgressIndicator(
                                            value: progress,
                                            backgroundColor: Colors.grey.shade200,
                                            valueColor: AlwaysStoppedAnimation<Color>(
                                              progress >= 1.0 ? Colors.green : Colors.orange,
                                            ),
                                            minHeight: 8,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(
                                        '${(progress * 100).toStringAsFixed(0)}%',
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                      ),
                                    ],
                                  ),
                                  if (theka.paymentMethod == 'Installment') ...[
                                    const SizedBox(height: 8),
                                    Text(
                                      'اقساط: $paidCount مکمل / ${insts.length} کل',
                                      style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      floatingActionButton: thekaProvider.thekas.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ThekaFormScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: const Text('نیا ٹھیکہ معاہدہ'),
              backgroundColor: Colors.brown.shade800,
              foregroundColor: Colors.white,
            )
          : null,
    );
  }

  // helper function to handle default or dummy ID
  int elementsId(int id) {
    return id;
  }

  Widget _buildSummaryHeader(double total, double paid, double pending, ThemeData theme) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.brown.shade800,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.brown.shade900.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text(
            'ٹھیکہ جات کا مالیاتی خلاصہ',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'Jameel Noori Nastaleeq',
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildHeaderItem('کل رقم', total, Colors.white),
              ),
              Container(width: 1, height: 40, color: Colors.white30),
              Expanded(
                child: _buildHeaderItem('ادا شدہ', paid, Colors.greenAccent),
              ),
              Container(width: 1, height: 40, color: Colors.white30),
              Expanded(
                child: _buildHeaderItem('باقی', pending, Colors.orangeAccent),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderItem(String label, double amount, Color color) {
    return Column(
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white60, fontSize: 13),
        ),
        const SizedBox(height: 4),
        Text(
          '${amount.toStringAsFixed(0)} روپے',
          style: TextStyle(
            color: color,
            fontSize: 17,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  Widget _buildAmountLabel(String label, double amount, Color amountColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
        ),
        const SizedBox(height: 2),
        Text(
          '${amount.toStringAsFixed(0)} روپے',
          style: TextStyle(
            color: amountColor,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ],
    );
  }
}
