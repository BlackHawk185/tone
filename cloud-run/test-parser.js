const { parseDispatchEmail } = require('./src/emailParser');

const body = `LCFD #5 Rip & Run
Report Time: 4/4/2026 00:07:50
Incident Date/Time: 4/4/2026 00:04:37
Incident Number(s): [2026-00000412 WY0110200], [2026-00000278 WYWHP0000], [2026-00000067 21523], [2026-00000031 21501], [2026-00000052 PBAMB]
EMS Incident Info: Accident - Unk Injury EMS Call Priority: 1
Fire Incident Info: Accident - Unk Injury Fire Call Priority: 1
Incident Location: MM401 I-80 Cross Streets: ROAD 212, US 30 / MUDDY CREEK DR, US 30
MM401 I-80
Fire Quadrant: FD5-FD3 EMS District: PBAMB
Google Maps link:
https://www.google.com/maps/search/?api=1&query=41.172368878,-104.083046751
Alerts:
Nature of Call: crash//across both sides of rd//eb and wb
Narrative:
***4/4/2026***
00:05:39 JENNIFER - ProQA Paramount Police: CC Text: TRAFFIC COLLISION
00:05:53 JENNIFER - trailer is in middle of highway wb//cab is on eb side
00:07:08 JENNIFER - ProQA Paramount Police: Dispatch Code: 131C01 (TRAFFIC COLLISION (unknown injury)) Response: 2 Officers ANSWERS: -- This is a TRAFFIC COLLISION. -- This incident just happened. -- Caller on scene. -- It is not known if anyone is injured. -- This is a HIGH MECHANISM collision. -- There is no one trapped or pinned. -- No one was thrown from the vehicle(s). -- No known hazards reported at the scene. -- One vehicle is involved. -- It is not known if all drivers are still on scene.
00:07:20 JENNIFER - rp pulled over//is walking back to check on crash
First Unit Dispatched: 4/4/2026 00:06:22
Dispatch Order:
1PD3
2WHP
3FD5FD5 - Fires and Accidents [FD5-FD3]
4FD3FD5 - Fires and Accidents [FD5-FD3]
5PineEMSPine EMS
FD3, FD5, PineEMS, PD3, WHP
Unit Status Times:
21501: Fire District #3
Assigned Station: FD3
Unit: FD3
Dispatched: 4/4/2026 00:07:49
21523: Fire District #5
Assigned Station: FD5
Unit: FD5
Dispatched: 4/4/2026 00:07:49
PBAMB: Pine Bluffs Ambulance
Assigned Station: Pine EMS
Unit: PineEMS
Dispatched: 4/4/2026 00:07:49
WY0110200: Pine Bluffs Police Department
Assigned Station: PBPD
Unit: PD3
Dispatched: 4/4/2026 00:06:22 Enroute: 4/4/2026 00:06:31
WYWHP0000: Wyoming Highway Patrol
Assigned Station: PBPD
Unit: WHP
Dispatched: 4/4/2026 00:07:38
For questions or to report issues about Rip & Runs, contact Rick (Rick.Fisher@laramiecountywy.gov) 637-6592.`;

const result = parseDispatchEmail('LCFD #5 Rip & Run', body);
console.log('=== EMS+Fire (Accident) ===');
console.log('  incidentType:', result.incidentType);
console.log('  incidentCategory:', result.incidentCategory);
console.log('  priority:', result.priority);
console.log();

// Fire-only call that was previously misclassified as EMS
const fireBody = `LCFD #5 Rip & Run
Report Time: 4/9/2026 16:40:22
Incident Date/Time: 4/9/2026 16:39:52
Incident Number(s): [2026-00000072 21523]
EMS Incident Info: EMS Call Priority:
Fire Incident Info: Service Call Fire Call Priority: 3
Incident Location: 801 MUDDY CREEK DR, Pine Bluffs Cross Streets: US 30 / DEAD END
Laramie County Weed & Pest - Pine
Fire Quadrant: FD5-FD3 EMS District: PBAMB
Google Maps link:
https://www.google.com/maps/search/?api=1&query=41.1763689457143,-104.079459770083
Alerts:
Nature of Call: fuel alarm
Narrative:
First Unit Dispatched: 4/9/2026 16:40:21
Dispatch Order:
1S53
S53
Unit Status Times:
21523: Fire District #5
Assigned Station: FD5
Unit: S53
Dispatched: 4/9/2026 16:40:21 Enroute: 4/9/2026 16:40:21 Arrived: 4/9/2026 16:40:21
For questions or to report issues about Rip & Runs, contact Rick (Rick.Fisher@laramiecountywy.gov) 637-6592.`;

const fireResult = parseDispatchEmail('LCFD #5 Rip & Run', fireBody);
console.log('=== Fire-only (Fuel Alarm) ===');
console.log('  incidentType:', fireResult.incidentType);
console.log('  incidentCategory:', fireResult.incidentCategory);
console.log('  priority:', fireResult.priority);
console.log('  natureOfCall:', fireResult.natureOfCall);

const grassFireBody = `LCFD #5 Rip & Run
Report Time: 4/11/2026 17:06:33
Incident Date/Time: 4/11/2026 17:04:59
Incident Number(s): [2026-00000074 21523], [2026-00000032 21501]
EMS Incident Info: EMS Call Priority:
Fire Incident Info: Fire - Grass Lg Struct Fire Call Priority: 2
Incident Location: 1526 STATE HWY 215, County Cross Streets: ROAD 215 / ROAD 216
Fire Quadrant: FD5-FD3 EMS District: PBAMB
Google Maps link:
https://www.google.com/maps/search/?api=1&query=41.2218816552064,-104.089560617787
Alerts:
Nature of Call: GRASS FIRE
Narrative:
***4/11/2026***
17:05:38 daye - ProQA Paramount Fire: CC Text: BRUSH/GRASS fire
17:06:16 daye - ProQA Paramount Fire: Dispatch Code: 82D07 (LARGE BRUSH/GRASS fire, structures THREATENED) Response: . ANSWERS: -- The caller is on scene (1st party). -- This is a BRUSH/GRASS fire. -- A LARGE area is burning. -- The fire has not been reported by the caller as extinguished. -- Residential areas are being threatened by the fire.
First Unit Dispatched: 4/11/2026 17:06:31
Dispatch Order:
1FD5FD5 - Fires and Accidents [FD5-FD3]
2FD3FD5 - Fires and Accidents [FD5-FD3]
FD3, FD5
Unit Status Times:
21501: Fire District #3
Assigned Station: FD3
Unit: FD3
Dispatched: 4/11/2026 17:06:31
21523: Fire District #5
Assigned Station: FD5
Unit: FD5
Dispatched: 4/11/2026 17:06:31
For questions or to report issues about Rip & Runs, contact Rick (Rick.Fisher@laramiecountywy.gov) 637-6592.`;

const grassFireResult = parseDispatchEmail('LCFD #5 Rip & Run', grassFireBody);
console.log();
console.log('=== Fire-only (Grass Fire) ===');
console.log('  incidentType:', grassFireResult.incidentType);
console.log('  incidentCategory:', grassFireResult.incidentCategory);
console.log('  priority:', grassFireResult.priority);
console.log('  natureOfCall:', grassFireResult.natureOfCall);
