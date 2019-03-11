'use strict';

Interceptor.attach(ObjC.classes.WWRobotInteractionManager['- serializeJsonToPackets:'].implementation, {
  onEnter: function (args) {
    this.json = JSON.parse(new ObjC.Object(args[2]).toString());
  },
  onLeave: function (retval) {
    console.log('\n-[WWRobotInteractionManager serializeJsonToPackets:]\n\tjson:\n\t\t' + JSON.stringify(this.json, null, 2).replace(/\n/g, '\n\t\t'));

    var packets = new ObjC.Object(retval);
    var count = packets.count().valueOf();
    for (var i = 0; i !== count; i++) {
      var packet = packets.objectAtIndex_(i);
      console.log('\tpackets[' + i + ']:\n\t\t' + hexdump(packet.bytes(), { length: packet.length(), header: false, ansi: true }).replace(/\n/g, '\n\t\t'));
    }
  }
});
