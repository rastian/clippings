import json, subprocess
result=json.loads(subprocess.check_output(['xcrun','simctl','list','devices','available','--json']))
for runtime, devices in sorted(result['devices'].items(), reverse=True):
    if 'iOS' in runtime:
        for device in devices:
            if device['name'].startswith('iPhone'):
                print('SIMULATOR_ID='+device['udid']); raise SystemExit(0)
raise SystemExit('No iPhone simulator runtime installed')
