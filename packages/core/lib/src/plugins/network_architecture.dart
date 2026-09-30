import 'plugin.dart';

/// Devices, links and zones for network architecture diagrams.
const networkArchitecturePlugin = BoardPlugin(
  id: 'network-architecture',
  name: 'Network architecture',
  description: 'Routers, switches, firewalls, servers and network zones for infrastructure diagrams.',
  version: '1.0.0',
  color: 0xFF0891B2,
  kinds: [
    ComponentKind(
      id: 'internet',
      label: 'Internet',
      icon: ComponentIcon([
        IconPath(
          'M7 19 H17.5 C20 19 22 17 22 14.5 C22 12.1 20.1 10.2 17.8 10 C17.1 6.6 14.3 4.5 11.5 4.5 '
          'C8.9 4.5 6.7 6.1 5.9 8.4 C3.7 8.9 2 10.8 2 13.2 C2 16.4 4.2 19 7 19 Z',
        ),
      ]),
    ),
    ComponentKind(
      id: 'router',
      label: 'Router',
      icon: ComponentIcon([
        IconCircle(12, 12, 9),
        IconLine(7, 12, 17, 12),
        IconLine(12, 7, 12, 17),
        IconPolyline([10, 9, 12, 7, 14, 9]),
        IconPolyline([10, 15, 12, 17, 14, 15]),
        IconPolyline([9, 10, 7, 12, 9, 14]),
        IconPolyline([15, 10, 17, 12, 15, 14]),
      ]),
    ),
    ComponentKind(
      id: 'switch',
      label: 'Switch',
      icon: ComponentIcon([
        IconRect(2.5, 6, 19, 12, radius: 2),
        IconLine(7, 10, 17, 10),
        IconPolyline([9, 8.25, 7, 10, 9, 11.75]),
        IconPolyline([15, 8.25, 17, 10, 15, 11.75]),
        IconLine(6, 14, 6, 15.5),
        IconLine(10, 14, 10, 15.5),
        IconLine(14, 14, 14, 15.5),
        IconLine(18, 14, 18, 15.5),
      ]),
    ),
    ComponentKind(
      id: 'firewall',
      label: 'Firewall',
      icon: ComponentIcon([
        IconRect(3, 5, 18, 14, radius: 1),
        IconLine(3, 9.67, 21, 9.67),
        IconLine(3, 14.33, 21, 14.33),
        IconLine(9, 5, 9, 9.67),
        IconLine(15, 5, 15, 9.67),
        IconLine(6, 9.67, 6, 14.33),
        IconLine(12, 9.67, 12, 14.33),
        IconLine(18, 9.67, 18, 14.33),
        IconLine(9, 14.33, 9, 19),
        IconLine(15, 14.33, 15, 19),
      ]),
    ),
    ComponentKind(
      id: 'load-balancer',
      label: 'Load balancer',
      icon: ComponentIcon([
        IconCircle(12, 5.5, 2.5),
        IconCircle(5, 18.5, 2.5),
        IconCircle(12, 18.5, 2.5),
        IconCircle(19, 18.5, 2.5),
        IconLine(12, 8, 5, 16),
        IconLine(12, 8, 12, 16),
        IconLine(12, 8, 19, 16),
      ]),
    ),
    ComponentKind(
      id: 'vpn-gateway',
      label: 'VPN gateway',
      icon: ComponentIcon([
        IconRect(5, 11, 14, 10, radius: 2),
        IconPath('M8 11 V8 C8 5.8 9.8 4 12 4 C14.2 4 16 5.8 16 8 V11'),
        IconCircle(12, 16, 1.3, filled: true),
      ]),
    ),
    ComponentKind(
      id: 'server',
      label: 'Server',
      icon: ComponentIcon([
        IconRect(4, 3.5, 16, 7.5, radius: 1.5),
        IconRect(4, 13, 16, 7.5, radius: 1.5),
        IconCircle(7.5, 7.25, 0.9, filled: true),
        IconCircle(7.5, 16.75, 0.9, filled: true),
        IconLine(11, 7.25, 16.5, 7.25),
        IconLine(11, 16.75, 16.5, 16.75),
      ]),
    ),
    ComponentKind(
      id: 'storage',
      label: 'Storage',
      icon: ComponentIcon([
        IconEllipse(12, 6, 7, 2.75),
        IconPath('M5 6 V18 C5 19.52 8.13 20.75 12 20.75 C15.87 20.75 19 19.52 19 18 V6'),
        IconPath('M5 12 C5 13.52 8.13 14.75 12 14.75 C15.87 14.75 19 13.52 19 12'),
      ]),
    ),
    ComponentKind(
      id: 'workstation',
      label: 'Workstation',
      icon: ComponentIcon([
        IconRect(3, 4, 18, 12, radius: 1.5),
        IconLine(12, 16, 12, 20),
        IconLine(8.5, 20, 15.5, 20),
      ]),
    ),
    ComponentKind(
      id: 'mobile-device',
      label: 'Mobile device',
      icon: ComponentIcon([
        IconRect(7, 2.5, 10, 19, radius: 2),
        IconLine(10.5, 18.5, 13.5, 18.5),
      ]),
    ),
    ComponentKind(
      id: 'access-point',
      label: 'Wireless AP',
      icon: ComponentIcon([
        IconCircle(12, 17.5, 1.3, filled: true),
        IconPath('M8.5 14 C10.4 12.1 13.6 12.1 15.5 14'),
        IconPath('M5.5 11 C9.1 7.4 14.9 7.4 18.5 11'),
      ]),
    ),
    ComponentKind(
      id: 'network-zone',
      label: 'Network zone',
      body: ComponentBody.zone,
      icon: ComponentIcon([
        IconRect(3, 5, 18, 14, radius: 2),
        IconLine(3, 9, 21, 9),
      ]),
    ),
  ],
);
