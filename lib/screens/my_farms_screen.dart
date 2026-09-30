import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/farm_provider.dart';
import '../providers/theka_provider.dart';
import '../models/models.dart';
import '../widgets/empty_state_widget.dart';
import '../utils/agricultural_units.dart';
import 'theka_details_screen.dart';
import 'theka_form_screen.dart';

class MyFarmsScreen extends StatefulWidget {
  const MyFarmsScreen({super.key});

  @override
  State<MyFarmsScreen> createState() => _MyFarmsScreenState();
}

class _MyFarmsScreenState extends State<MyFarmsScreen> {
  @override
  Widget build(BuildContext context) {
    final farmProvider = Provider.of<FarmProvider>(context);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('میری زمینیں'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_location_alt_outlined),
            tooltip: 'نئی زمین شامل کریں',
            onPressed: () => _showAddFarmDialog(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          await farmProvider.fetchFarms();
          if (context.mounted) {
            await Provider.of<ThekaProvider>(
              context,
              listen: false,
            ).fetchThekas();
          }
        },
        child:
            farmProvider.farms.isEmpty
            ? SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                    height:
                        MediaQuery.of(context).size.height -
                        kToolbarHeight -
                        MediaQuery.of(context).padding.top,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const EmptyStateWidget(
                        message: 'کوئی زمین موجود نہیں ہے',
                        subtitle: 'نئی زمین شامل کرنے کے لیے نیچے بٹن دبائیں',
                        fallbackIcon: Icons.landscape,
                        imageAsset: 'assets/images/wheat.png',
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () => _showAddFarmDialog(context),
                        child: const Text('نئی زمین شامل کریں'),
                      ),
                    ],
                  ),
                ),
              )
            : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: farmProvider.farms.length,
              itemBuilder: (context, index) {
                final farm = farmProvider.farms[index];
                final fields = farmProvider.getFieldsForFarm(farm.id!);

                return Card(
                  elevation: 3,
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: ExpansionTile(
                    title: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          farm.name,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _showEditFarmDialog(context, farm);
                            } else if (value == 'delete') {
                                  _showDeleteConfirmDialog(
                                    context,
                                    isFarm: true,
                                    id: farm.id!,
                                    name: farm.name,
                                  );
                            }
                          },
                              itemBuilder:
                                  (BuildContext context) =>
                                      <PopupMenuEntry<String>>[
                            const PopupMenuItem<String>(
                              value: 'edit',
                              child: ListTile(
                                            leading: Icon(
                                              Icons.edit,
                                              color: Colors.blue,
                                            ),
                                title: Text('ترمیم کریں'),
                              ),
                            ),
                            const PopupMenuItem<String>(
                              value: 'delete',
                              child: ListTile(
                                            leading: Icon(
                                              Icons.delete,
                                              color: Colors.red,
                                            ),
                                title: Text('حذف کریں'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    subtitle: Text(
                      'کل رقبہ: ${farm.totalArea} ایکڑ',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade600,
                          ),
                    ),
                    leading: CircleAvatar(
                          backgroundColor: theme.colorScheme.primary.withValues(
                            alpha: 0.1,
                          ),
                          child: Icon(
                            Icons.landscape,
                            color: theme.colorScheme.primary,
                          ),
                    ),
                    children: [
                      const Divider(),
                      _buildThekaSection(context, farm.id!, farm.name),
                      const Divider(),
                      if (fields.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Text(
                            'اس زمین میں کوئی کھیت موجود نہیں ہے',
                                style: TextStyle(
                                  fontSize: 16,
                                  color: Colors.grey.shade600,
                                ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: fields.length,
                          itemBuilder: (context, fIndex) {
                            final field = fields[fIndex];
                            return ListTile(
                              title: Text(
                                field.name,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              subtitle: Text(
                                'سائز: ${field.sizeAcres} ایکڑ | نہری پانی: ${field.canalWaterAvailable == 1 ? 'ہاں' : 'ناں'} | ٹیوب ویل: ${field.tubeWellAvailable == 1 ? 'ہاں' : 'ناں'}',
                                style: const TextStyle(fontSize: 14),
                              ),
                                  leading: const Icon(
                                    Icons.grid_on,
                                    color: Colors.green,
                                  ),
                              trailing: PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _showEditFieldDialog(context, field);
                                  } else if (value == 'delete') {
                                        _showDeleteConfirmDialog(
                                          context,
                                          isFarm: false,
                                          id: field.id!,
                                          name: field.name,
                                          parentId: farm.id,
                                        );
                                  }
                                },
                                    itemBuilder:
                                        (BuildContext context) =>
                                            <PopupMenuEntry<String>>[
                                  const PopupMenuItem<String>(
                                    value: 'edit',
                                    child: ListTile(
                                                  leading: Icon(
                                                    Icons.edit,
                                                    color: Colors.blue,
                                                  ),
                                      title: Text('ترمیم کریں'),
                                    ),
                                  ),
                                  const PopupMenuItem<String>(
                                    value: 'delete',
                                    child: ListTile(
                                                  leading: Icon(
                                                    Icons.delete,
                                                    color: Colors.red,
                                                  ),
                                      title: Text('حذف کریں'),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: OutlinedButton.icon(
                              onPressed:
                                  () => _showAddFieldDialog(context, farm.id!),
                          icon: const Icon(Icons.add),
                          label: const Text('نیا کھیت شامل کریں'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 45),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
      ),
    );
  }

  void _showAddFarmDialog(BuildContext context) {
    final nameController = TextEditingController();
    final areaController = TextEditingController();
    final formKey = GlobalKey<FormState>();
    String selectedAreaUnit = 'acre';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('نئی زمین شامل کریں'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'زمین کا نام (مثال: طلحہ فارم)',
                    border: OutlineInputBorder(),
                  ),
                  validator:
                      (value) =>
                          value!.isEmpty
                              ? 'براہ کرم زمین کا نام درج کریں'
                              : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedAreaUnit,
                  decoration: const InputDecoration(
                    labelText: 'رقبے کی اکائی',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'acre', child: Text('ایکڑ')),
                    DropdownMenuItem(value: 'kanal', child: Text('کنال')),
                    DropdownMenuItem(value: 'marla', child: Text('مرلہ')),
                  ],
                  onChanged: (value) {
                    if (value != null) selectedAreaUnit = value;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: areaController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'کل رقبہ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final area = double.tryParse(value ?? '');
                    if (area == null || !area.isFinite || area <= 0) {
                      return 'صفر سے زیادہ درست رقبہ درج کریں';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('کینسل'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Provider.of<FarmProvider>(context, listen: false).addFarm(
                    nameController.text,
                    AgriculturalUnits.areaToAcres(
                    double.parse(areaController.text),
                      selectedAreaUnit,
                    ),
                  );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('محفوظ کریں'),
            ),
          ],
        );
      },
    );
  }

  void _showEditFarmDialog(BuildContext context, Farm farm) {
    final nameController = TextEditingController(text: farm.name);
    final areaController = TextEditingController(
      text: farm.totalArea.toString(),
    );
    final formKey = GlobalKey<FormState>();
    String selectedAreaUnit = 'acre';

    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('زمین میں ترمیم کریں'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: 'زمین کا نام',
                    border: OutlineInputBorder(),
                  ),
                  validator:
                      (value) =>
                          value!.isEmpty ? 'براہ کرم نام درج کریں' : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: selectedAreaUnit,
                  decoration: const InputDecoration(
                    labelText: 'رقبے کی اکائی',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'acre', child: Text('ایکڑ')),
                    DropdownMenuItem(value: 'kanal', child: Text('کنال')),
                    DropdownMenuItem(value: 'marla', child: Text('مرلہ')),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    final current = double.tryParse(areaController.text);
                    if (current != null && current.isFinite && current >= 0) {
                      final acres = AgriculturalUnits.areaToAcres(
                        current,
                        selectedAreaUnit,
                      );
                      areaController.text = AgriculturalUnits.areaFromAcres(
                        acres,
                        value,
                      ).toStringAsFixed(3);
                    }
                    selectedAreaUnit = value;
                  },
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: areaController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'کل رقبہ',
                    border: OutlineInputBorder(),
                  ),
                  validator: (value) {
                    final area = double.tryParse(value ?? '');
                    if (area == null || !area.isFinite || area <= 0) {
                      return 'صفر سے زیادہ درست رقبہ درج کریں';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('کینسل'),
            ),
            ElevatedButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Provider.of<FarmProvider>(context, listen: false).updateFarm(
                    farm.id!,
                    nameController.text,
                    AgriculturalUnits.areaToAcres(
                    double.parse(areaController.text),
                      selectedAreaUnit,
                    ),
                  );
                  Navigator.pop(ctx);
                }
              },
              child: const Text('محفوظ کریں'),
            ),
          ],
        );
      },
    );
  }

  void _showAddFieldDialog(BuildContext context, int farmId) {
    final nameController = TextEditingController();
    final sizeController = TextEditingController();
    bool canalWater = false;
    bool tubeWell = false;
    final formKey = GlobalKey<FormState>();
    String selectedAreaUnit = 'acre';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('نیا کھیت شامل کریں'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'کھیت کا نام (مثال: کھیت نمبر 1)',
                          border: OutlineInputBorder(),
                        ),
                        validator:
                            (value) =>
                                value!.isEmpty ? 'براہ کرم نام درج کریں' : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedAreaUnit,
                        decoration: const InputDecoration(
                          labelText: 'رقبے کی اکائی',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'acre', child: Text('ایکڑ')),
                          DropdownMenuItem(value: 'kanal', child: Text('کنال')),
                          DropdownMenuItem(value: 'marla', child: Text('مرلہ')),
                        ],
                        onChanged: (value) {
                          if (value != null) selectedAreaUnit = value;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: sizeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'رقبہ',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final area = double.tryParse(value ?? '');
                          if (area == null || !area.isFinite || area <= 0) {
                            return 'صفر سے زیادہ درست رقبہ درج کریں';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('نہری پانی دستیاب ہے؟'),
                        value: canalWater,
                        onChanged: (val) {
                          setState(() {
                            canalWater = val ?? false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        title: const Text('ٹیوب ویل دستیاب ہے؟'),
                        value: tubeWell,
                        onChanged: (val) {
                          setState(() {
                            tubeWell = val ?? false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('کینسل'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Provider.of<FarmProvider>(
                        context,
                        listen: false,
                      ).addField(
                        farmId: farmId,
                        name: nameController.text,
                        sizeAcres: AgriculturalUnits.areaToAcres(
                          double.parse(sizeController.text),
                          selectedAreaUnit,
                        ),
                        canalWaterAvailable: canalWater ? 1 : 0,
                        tubeWellAvailable: tubeWell ? 1 : 0,
                      );
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('محفوظ کریں'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEditFieldDialog(BuildContext context, Field field) {
    final nameController = TextEditingController(text: field.name);
    final sizeController = TextEditingController(
      text: field.sizeAcres.toString(),
    );
    bool canalWater = field.canalWaterAvailable == 1;
    bool tubeWell = field.tubeWellAvailable == 1;
    final formKey = GlobalKey<FormState>();
    String selectedAreaUnit = 'acre';

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('کھیت میں ترمیم کریں'),
              content: Form(
                key: formKey,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextFormField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'کھیت کا نام',
                          border: OutlineInputBorder(),
                        ),
                        validator:
                            (value) =>
                                value!.isEmpty ? 'براہ کرم نام درج کریں' : null,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        initialValue: selectedAreaUnit,
                        decoration: const InputDecoration(
                          labelText: 'رقبے کی اکائی',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'acre', child: Text('ایکڑ')),
                          DropdownMenuItem(value: 'kanal', child: Text('کنال')),
                          DropdownMenuItem(value: 'marla', child: Text('مرلہ')),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          final current = double.tryParse(sizeController.text);
                          if (current != null &&
                              current.isFinite &&
                              current >= 0) {
                            final acres = AgriculturalUnits.areaToAcres(
                              current,
                              selectedAreaUnit,
                            );
                            sizeController
                                .text = AgriculturalUnits.areaFromAcres(
                              acres,
                              value,
                            ).toStringAsFixed(3);
                          }
                          selectedAreaUnit = value;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: sizeController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: const InputDecoration(
                          labelText: 'رقبہ',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          final area = double.tryParse(value ?? '');
                          if (area == null || !area.isFinite || area <= 0) {
                            return 'صفر سے زیادہ درست رقبہ درج کریں';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      CheckboxListTile(
                        title: const Text('نہری پانی دستیاب ہے؟'),
                        value: canalWater,
                        onChanged: (val) {
                          setState(() {
                            canalWater = val ?? false;
                          });
                        },
                      ),
                      CheckboxListTile(
                        title: const Text('ٹیوب ویل دستیاب ہے؟'),
                        value: tubeWell,
                        onChanged: (val) {
                          setState(() {
                            tubeWell = val ?? false;
                          });
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('کینسل'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (formKey.currentState!.validate()) {
                      Provider.of<FarmProvider>(
                        context,
                        listen: false,
                      ).updateField(
                        id: field.id!,
                        farmId: field.farmId,
                        name: nameController.text,
                        sizeAcres: AgriculturalUnits.areaToAcres(
                          double.parse(sizeController.text),
                          selectedAreaUnit,
                        ),
                        canalWaterAvailable: canalWater ? 1 : 0,
                        tubeWellAvailable: tubeWell ? 1 : 0,
                      );
                      Navigator.pop(ctx);
                    }
                  },
                  child: const Text('محفوظ کریں'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteConfirmDialog(
    BuildContext context, {
    required bool isFarm,
    required int id,
    required String name,
    int? parentId,
  }) {
    showDialog(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: Text(isFarm ? 'زمین حذف کریں؟' : 'کھیت حذف کریں؟'),
          content: Text(
            isFarm
                ? 'کیا آپ واقعی "$name" کو حذف کرنا چاہتے ہیں؟ اس سے متعلقہ تمام کھیت بھی حذف ہو جائیں گے۔'
                : 'کیا آپ واقعی کھیت "$name" کو حذف کرنا چاہتے ہیں؟',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('کینسل'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                final provider = Provider.of<FarmProvider>(
                  context,
                  listen: false,
                );
                if (isFarm) {
                  provider.deleteFarm(id);
                } else {
                  provider.deleteField(id, parentId!);
                }
                Navigator.pop(ctx);
              },
              child: const Text(
                'حذف کریں',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildThekaSection(BuildContext context, int farmId, String farmName) {
    final thekaProvider = Provider.of<ThekaProvider>(context);
    final currentThekas =
        thekaProvider.thekas.where((t) => t.farmId == farmId).toList();

    if (currentThekas.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'ٹھیکہ (لیز): کوئی معاہدہ نہیں ہے',
              style: TextStyle(
                fontSize: 14,
                fontStyle: FontStyle.italic,
                color: Colors.grey,
              ),
            ),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const ThekaFormScreen()),
                );
              },
              icon: const Icon(Icons.add, size: 16, color: Colors.brown),
              label: const Text(
                'ٹھیکہ شامل کریں',
                style: TextStyle(color: Colors.brown, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }

    final theka = currentThekas.first;
    final insts = thekaProvider.getInstallmentsForTheka(theka.id!);
    double paidAmt = 0.0;
    for (var inst in insts) {
      paidAmt += inst.paidAmount;
    }
    final double pendingAmt = theka.totalAmount - paidAmt;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'ٹھیکہ (لیز معاہدہ)',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  color: Colors.brown,
                ),
              ),
              TextButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ThekaDetailsScreen(thekaId: theka.id!),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.info_outline,
                  size: 16,
                  color: Colors.brown,
                ),
                label: const Text(
                  'تفصیلات',
                  style: TextStyle(color: Colors.brown, fontSize: 13),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'کل ٹھیکہ: ${theka.totalAmount.toStringAsFixed(0)} روپے',
                style: const TextStyle(fontSize: 13),
              ),
              Text(
                'ادا شدہ: ${paidAmt.toStringAsFixed(0)} روپے',
                style: const TextStyle(fontSize: 13, color: Colors.green),
              ),
              Text(
                'باقی: ${pendingAmt.toStringAsFixed(0)} روپے',
                style: const TextStyle(fontSize: 13, color: Colors.red),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
