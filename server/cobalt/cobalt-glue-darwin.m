#include "cobalt.h"

#import <CoreBluetooth/CoreBluetooth.h>

@interface CobaltPeripheralManagerHandle : NSObject <CBCentralManagerDelegate> {
  @public CobaltPeripheralManager *wrapper;
  @public CBCentralManager *impl;
}
@end

@interface CobaltPeripheralHandle : NSObject <CBPeripheralDelegate> {
  @public CobaltPeripheral *wrapper;
  @public CBPeripheral *impl;
}

- (instancetype)initWithImplementation:(CBPeripheral *)theImpl
                               manager:(CobaltPeripheralManager *)manager;

@end

@implementation CobaltPeripheralManagerHandle

- (instancetype)initWithWrapper:(CobaltPeripheralManager *)theWrapper {
  self = [super init];

  if (self != nil) {
    wrapper = theWrapper;
    impl = nil;
  }

  return self;
}

- (void)start {
  impl = [[CBCentralManager alloc] initWithDelegate:self queue:nil];
  _cobalt_peripheral_manager_on_state_changed(wrapper, impl.state);
}

- (void)startScan:(NSArray<CBUUID *> *)uuids {
  [impl scanForPeripheralsWithServices:uuids
                               options:@{}];
}

- (void)stopScan {
  [impl stopScan];
  _cobalt_peripheral_manager_on_scan_stopped(wrapper);
}

- (void)connectPeripheral:(CobaltPeripheralHandle *)peripheralHandle {
  [impl connectPeripheral:peripheralHandle->impl
                  options:nil];
}

- (void)cancelPeripheralConnection:(CobaltPeripheralHandle *)peripheralHandle {
  [impl cancelPeripheralConnection:peripheralHandle->impl];
}

- (void)centralManagerDidUpdateState:(CBCentralManager *)central {
  _cobalt_peripheral_manager_on_state_changed(wrapper, impl.state);
}

- (void)centralManager:(CBCentralManager *)central
 didDiscoverPeripheral:(CBPeripheral *)peripheral
     advertisementData:(NSDictionary<NSString *, id> *)advertisementData
                  RSSI:(NSNumber *)RSSI {
  CobaltPeripheralHandle *peripheralHandle = [[CobaltPeripheralHandle alloc] initWithImplementation:peripheral
                                                                                            manager:wrapper];
  _cobalt_peripheral_manager_on_scan_match_found(wrapper, peripheralHandle->wrapper);
}

- (void)centralManager:(CBCentralManager *)central
  didConnectPeripheral:(CBPeripheral *)peripheral {
  _cobalt_peripheral_manager_on_connect_success(wrapper, (__bridge gpointer) peripheral);
}

- (void)centralManager:(CBCentralManager *)central
didFailToConnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
  _cobalt_peripheral_manager_on_connect_failure(wrapper, (__bridge gpointer) peripheral, error.localizedDescription.UTF8String);
}

- (void)centralManager:(CBCentralManager *)central
didDisconnectPeripheral:(CBPeripheral *)peripheral
                 error:(NSError *)error {
  _cobalt_peripheral_manager_on_disconnect(wrapper, (__bridge gpointer) peripheral, error.localizedDescription.UTF8String);
}

@end

gpointer _cobalt_peripheral_manager_open(CobaltPeripheralManager *wrapper) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *handle = [[CobaltPeripheralManagerHandle alloc] initWithWrapper:wrapper];
    dispatch_async(dispatch_get_main_queue(), ^{
      [handle start];
    });
    return (__bridge_retained gpointer) handle;
  }
}

void _cobalt_peripheral_manager_close(CobaltPeripheralManager *wrapper, gpointer opaqueHandle) {
  @autoreleasepool {
    g_object_ref(wrapper);
    dispatch_async(dispatch_get_main_queue(), ^{
      CobaltPeripheralManagerHandle *handle = (__bridge_transfer CobaltPeripheralManagerHandle *) opaqueHandle;
      handle = nil;
      g_object_unref(wrapper);
    });
  }
}

void _cobalt_peripheral_manager_start_scan(CobaltPeripheralManager *wrapper, gchar **uuids, int uuidsLength) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *managerHandle = (__bridge CobaltPeripheralManagerHandle *) wrapper->handle;

    NSMutableArray *uuidValues = [NSMutableArray arrayWithCapacity:uuidsLength];
    for (int i = 0; i != uuidsLength; i++) {
      [uuidValues addObject:[CBUUID UUIDWithString:[NSString stringWithUTF8String:uuids[i]]]];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
      [managerHandle startScan:uuidValues];
    });
  }
}

void _cobalt_peripheral_manager_stop_scan(CobaltPeripheralManager *wrapper) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *managerHandle = (__bridge CobaltPeripheralManagerHandle *) wrapper->handle;

    dispatch_async(dispatch_get_main_queue(), ^{
      [managerHandle stopScan];
    });
  }
}

void _cobalt_peripheral_manager_connect_peripheral(CobaltPeripheralManager *wrapper, CobaltPeripheral *peripheral) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *managerHandle = (__bridge CobaltPeripheralManagerHandle *) wrapper->handle;
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) peripheral->handle;

    dispatch_async(dispatch_get_main_queue(), ^{
        [managerHandle connectPeripheral:peripheralHandle];
    });
  }
}

void _cobalt_peripheral_manager_cancel_peripheral_connection(CobaltPeripheralManager *wrapper, CobaltPeripheral *peripheral) {
  @autoreleasepool {
    CobaltPeripheralManagerHandle *managerHandle = (__bridge CobaltPeripheralManagerHandle *) wrapper->handle;
    CobaltPeripheralHandle *peripheralHandle = (__bridge CobaltPeripheralHandle *) peripheral->handle;

    dispatch_async(dispatch_get_main_queue(), ^{
        [managerHandle cancelPeripheralConnection:peripheralHandle];
    });
  }
}

@implementation CobaltPeripheralHandle

- (instancetype)initWithImplementation:(CBPeripheral *)theImpl
                               manager:(CobaltPeripheralManager *)manager {
  self = [super init];

  if (self != nil) {
    wrapper = cobalt_peripheral_new(manager);
    impl = theImpl;

    wrapper->handle = (__bridge_retained gpointer) self;
  }

  return self;
}

@end

gpointer _cobalt_peripheral_get_implementation(CobaltPeripheral *wrapper) {
  CobaltPeripheralHandle *handle = (__bridge CobaltPeripheralHandle *) wrapper->handle;
  return (__bridge gpointer) handle->impl;
}
