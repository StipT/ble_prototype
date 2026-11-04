import 'package:flutter/material.dart';

import '../../data/fake/fake_ppg_device.dart';

/// Debug-only controls for the [FakePpgDevice] fault knobs, so every
/// failure path (drops, outages, gaps, Bluetooth off) can be triggered by
/// hand on a simulator. Only shown when the fake device is wired in.
///
/// The knobs are plain fields on the simulator (no streams), so local
/// `setState` is enough to reflect them.
class DebugFaultPanel extends StatefulWidget {
  /// [device] is the simulator to drive.
  const DebugFaultPanel({required this.device, super.key});

  /// Simulated wearable.
  final FakePpgDevice device;

  @override
  State<DebugFaultPanel> createState() => _DebugFaultPanelState();
}

class _DebugFaultPanelState extends State<DebugFaultPanel> {
  FakePpgDevice get _d => widget.device;

  void _update(VoidCallback change) => setState(change);

  void _toast(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  @override
  Widget build(BuildContext context) => Card(
    key: const Key('debug-fault-panel'),
    child: ExpansionTile(
      leading: const Icon(Icons.bug_report),
      title: const Text('Debug fault panel (fake device)'),
      childrenPadding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton(
              key: const Key('fault-disconnect'),
              onPressed: () {
                _d.simulateDisconnect();
                _toast('Link dropped');
              },
              child: const Text('Drop link'),
            ),
            OutlinedButton(
              key: const Key('fault-outage'),
              onPressed: () {
                _d.simulateOutage(const Duration(seconds: 10));
                _toast('Out of range for 10 s');
              },
              child: const Text('Outage 10 s'),
            ),
            OutlinedButton(
              key: const Key('fault-drop-packets'),
              onPressed: () {
                _d.dropNextPackets(20);
                _toast('Dropping next 20 packets');
              },
              child: const Text('Drop 20 packets'),
            ),
          ],
        ),
        SwitchListTile(
          key: const Key('fault-bluetooth'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Phone Bluetooth on'),
          value: _d.bluetoothEnabled,
          onChanged: (v) => _update(() => _d.bluetoothEnabled = v),
        ),
        SwitchListTile(
          key: const Key('fault-charging'),
          contentPadding: EdgeInsets.zero,
          title: const Text('Device on charger'),
          value: _d.charging,
          onChanged: (v) => _update(() => _d.charging = v),
        ),
        _slider(
          label: 'Packet loss',
          value: _d.packetDropProbability,
          max: 0.5,
          display: '${(_d.packetDropProbability * 100).round()} %',
          onChanged: (v) => _d.packetDropProbability = v,
        ),
        _slider(
          label: 'Random drops / min',
          value: _d.randomDisconnectsPerMinute,
          max: 6,
          display: _d.randomDisconnectsPerMinute.toStringAsFixed(1),
          onChanged: (v) => _d.randomDisconnectsPerMinute = v,
        ),
        _slider(
          label: 'Heart rate',
          value: _d.heartRateBpm,
          min: 40,
          max: 180,
          display: '${_d.heartRateBpm.round()} bpm',
          onChanged: (v) => _d.heartRateBpm = v,
        ),
        const SizedBox(height: 8),
      ],
    ),
  );

  Widget _slider({
    required String label,
    required double value,
    required double max,
    required String display,
    required ValueChanged<double> onChanged,
    double min = 0,
  }) => Row(
    children: [
      SizedBox(width: 130, child: Text(label)),
      Expanded(
        child: Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          onChanged: (v) => _update(() => onChanged(v)),
        ),
      ),
      SizedBox(width: 64, child: Text(display, textAlign: TextAlign.end)),
    ],
  );
}
