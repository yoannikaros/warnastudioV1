import 'package:flutter/material.dart';
import '../services/bluetooth_printer_service.dart';

class BluetoothPrinterDialog extends StatefulWidget {
  final Function(PrinterBluetoothInfo)? onDeviceSelected;

  const BluetoothPrinterDialog({
    super.key,
    this.onDeviceSelected,
  });

  @override
  State<BluetoothPrinterDialog> createState() => _BluetoothPrinterDialogState();
}

class _BluetoothPrinterDialogState extends State<BluetoothPrinterDialog> {
  final BluetoothPrinterService _printerService = BluetoothPrinterService();
  List<PrinterBluetoothInfo> _devices = [];
  bool _isScanning = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scanForDevices();
  }

  Future<void> _scanForDevices() async {
    setState(() {
      _isScanning = true;
      _errorMessage = null;
    });

    try {
      final devices = await _printerService.getPairedDevices();
      setState(() {
        _devices = devices;
        _isScanning = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
        _isScanning = false;
      });
    }
  }

  Future<void> _connectToDevice(PrinterBluetoothInfo device) async {
    try {
      bool connected = await _printerService.connectToPrinter(device);
      if (connected && mounted) {
        widget.onDeviceSelected?.call(device);
        Navigator.of(context).pop(device);
      } else if (mounted) {
        setState(() {
          _errorMessage = 'Failed to connect to ${device.name}';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'Error connecting: ${e.toString()}';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text(
        'Pilih Printer Bluetooth',
        style: TextStyle(
          color: Color(0xFF8B7355),
          fontWeight: FontWeight.w600,
        ),
      ),
      content: SizedBox(
        width: double.maxFinite,
        height: 400,
        child: Column(
          children: [
            if (_errorMessage != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, color: Colors.red.shade600),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(color: Colors.red.shade700),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Perangkat yang ditemukan:',
                  style: TextStyle(
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF8B7355),
                  ),
                ),
                IconButton(
                  onPressed: _isScanning ? null : _scanForDevices,
                  icon: _isScanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB8956A)),
                          ),
                        )
                      : const Icon(Icons.refresh, color: Color(0xFFB8956A)),
                  tooltip: 'Scan ulang',
                ),
              ],
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _isScanning
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFB8956A)),
                          ),
                          SizedBox(height: 16),
                          Text(
                            'Mencari perangkat Bluetooth...',
                            style: TextStyle(color: Color(0xFF8B7355)),
                          ),
                        ],
                      ),
                    )
                  : _devices.isEmpty
                      ? const Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.bluetooth_disabled,
                                size: 48,
                                color: Color(0xFFB8956A),
                              ),
                              SizedBox(height: 16),
                              Text(
                                'Tidak ada perangkat ditemukan',
                                style: TextStyle(color: Color(0xFF8B7355)),
                              ),
                              SizedBox(height: 8),
                              Text(
                                'Pastikan printer Bluetooth sudah menyala\ndan dalam mode pairing',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Color(0xFF8B7355),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _devices.length,
                          itemBuilder: (context, index) {
                            final device = _devices[index];
                            return Card(
                              margin: const EdgeInsets.symmetric(vertical: 4),
                              child: ListTile(
                                leading: const Icon(
                                  Icons.print,
                                  color: Color(0xFFB8956A),
                                ),
                                title: Text(
                                  device.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF8B7355),
                                  ),
                                ),
                                subtitle: Text(
                                  device.macAdress,
                                  style: const TextStyle(
                                    color: Color(0xFF8B7355),
                                    fontSize: 12,
                                  ),
                                ),
                                trailing: const Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color: Color(0xFFB8956A),
                                ),
                                onTap: () => _connectToDevice(device),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Batal',
            style: TextStyle(color: Color(0xFF8B7355)),
          ),
        ),
      ],
    );
  }
}