from driver import *
save('index-refresh-complete.json',multi('refresh-complete','refresh',{'goal':'exchange'}))
save('publish-reader.json',multi('publish-reader','publish',{'goal':'exchange','audience':'reader'}))
read=multi('read-reader-complete','read',{'goal':'exchange'},principal='reader');save('read-reader-complete.json',read)
save('query-reader-complete.json',multi('query-reader-complete','query',{'goal':'exchange'},principal='reader'))
save('wiki-reader-complete.json',multi('wiki-reader-complete','wiki',{'goal':'exchange'},principal='reader'))
print(json.dumps(read,ensure_ascii=False)[:2200])
