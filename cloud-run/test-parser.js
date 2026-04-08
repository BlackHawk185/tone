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
console.log(JSON.stringify(result, null, 2));
