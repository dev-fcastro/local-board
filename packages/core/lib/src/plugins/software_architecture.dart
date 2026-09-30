import 'plugin.dart';

const _cylinder = [
  IconEllipse(12, 6, 7, 2.75),
  IconPath('M5 6 V18 C5 19.52 8.13 20.75 12 20.75 C15.87 20.75 19 19.52 19 18 V6'),
  IconPath('M5 12 C5 13.52 8.13 14.75 12 14.75 C15.87 14.75 19 13.52 19 12'),
];

/// Services, data stores and clients for software architecture diagrams.
const softwareArchitecturePlugin = BoardPlugin(
  id: 'software-architecture',
  name: 'Software architecture',
  description: 'Services, databases, queues, clients and boundaries for system diagrams.',
  version: '1.0.0',
  color: 0xFF4F46E5,
  kinds: [
    ComponentKind(
      id: 'user',
      label: 'User',
      icon: ComponentIcon([
        IconCircle(12, 7.5, 3.5),
        IconPath('M5 20 C5 16.1 8.1 13 12 13 C15.9 13 19 16.1 19 20'),
      ]),
    ),
    ComponentKind(
      id: 'web-app',
      label: 'Web app',
      icon: ComponentIcon([
        IconRect(3, 4.5, 18, 15, radius: 2),
        IconLine(3, 8.5, 21, 8.5),
        IconCircle(5.75, 6.5, 0.6, filled: true),
        IconCircle(7.75, 6.5, 0.6, filled: true),
        IconCircle(9.75, 6.5, 0.6, filled: true),
      ]),
    ),
    ComponentKind(
      id: 'mobile-app',
      label: 'Mobile app',
      icon: ComponentIcon([
        IconRect(7, 2.5, 10, 19, radius: 2),
        IconLine(10.5, 18.5, 13.5, 18.5),
      ]),
    ),
    ComponentKind(
      id: 'api-gateway',
      label: 'API gateway',
      icon: ComponentIcon([
        IconRect(9, 3.5, 6, 17, radius: 1.5),
        IconLine(2.5, 12, 9, 12),
        IconPolyline([6, 9.5, 8.5, 12, 6, 14.5]),
        IconLine(15, 12, 21.5, 12),
        IconPolyline([19, 9.5, 21.5, 12, 19, 14.5]),
      ]),
    ),
    ComponentKind(
      id: 'service',
      label: 'Service',
      icon: ComponentIcon([
        IconPolyline([12, 2.5, 20.25, 7.25, 20.25, 16.75, 12, 21.5, 3.75, 16.75, 3.75, 7.25], closed: true),
        IconCircle(12, 12, 3),
      ]),
    ),
    ComponentKind(
      id: 'function',
      label: 'Function',
      icon: ComponentIcon([
        IconPolyline([8, 7, 3, 12, 8, 17]),
        IconPolyline([16, 7, 21, 12, 16, 17]),
        IconLine(14, 5, 10, 19),
      ]),
    ),
    ComponentKind(id: 'database', label: 'Database', icon: ComponentIcon(_cylinder)),
    ComponentKind(
      id: 'cache',
      label: 'Cache',
      icon: ComponentIcon([
        IconPolyline([13, 2.5, 5, 13.5, 11, 13.5, 10, 21.5, 19, 10, 13, 10], closed: true),
      ]),
    ),
    ComponentKind(
      id: 'queue',
      label: 'Message queue',
      icon: ComponentIcon([
        IconRect(2, 8, 4, 8, radius: 1),
        IconRect(7, 8, 4, 8, radius: 1),
        IconRect(12, 8, 4, 8, radius: 1),
        IconLine(17.5, 12, 22, 12),
        IconPolyline([20, 10, 22, 12, 20, 14]),
      ]),
    ),
    ComponentKind(
      id: 'file-storage',
      label: 'File storage',
      icon: ComponentIcon([
        IconPolyline([3, 6, 9, 6, 11, 8.5, 21, 8.5, 21, 19, 3, 19], closed: true),
      ]),
    ),
    ComponentKind(
      id: 'background-job',
      label: 'Background job',
      icon: ComponentIcon([
        IconCircle(12, 12, 8.5),
        IconPolyline([12, 7, 12, 12, 15.5, 14]),
      ]),
    ),
    ComponentKind(
      id: 'external-system',
      label: 'External system',
      icon: ComponentIcon([
        IconCircle(12, 12, 9),
        IconEllipse(12, 12, 4, 9),
        IconLine(3, 12, 21, 12),
      ]),
    ),
    ComponentKind(
      id: 'system-boundary',
      label: 'System boundary',
      body: ComponentBody.zone,
      icon: ComponentIcon([
        IconRect(3, 3, 18, 18, radius: 3),
        IconRect(7.5, 7.5, 9, 9, radius: 1.5),
      ]),
    ),
  ],
);
