import runpy
p=runpy.run_path('/private/tmp/stage5-work/live/code-first/producer/app.py')
c=runpy.run_path('/private/tmp/stage5-work/live/code-first/consumer/app.py')
payload=p['emit']()
assert payload == {'total': 10}, payload
assert c['parse'](payload) == 10
print('integration total=10 verified')
