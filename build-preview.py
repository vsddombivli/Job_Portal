"""Create the downloadable, single-file demo from the same production UI."""
from pathlib import Path
import re
root=Path(__file__).parent
parts=[]
for filename in ['core.js','demo.js','resume.js','app.js']:
    source=(root/filename).read_text()
    source=re.sub(r'^import .*;\n','',source,flags=re.M)
    source=re.sub(r'^export ','',source,flags=re.M)
    parts.append(source)
script='\n'.join(parts)+"\nstate.demo=true;demoData=seedDemo();state.admin=false;state.page='jobs';load();\n"
html=(root/'index.html').read_text().replace('<link rel="stylesheet" href="styles.css">','<style>\n'+(root/'styles.css').read_text()+'\n</style>')
html=html.replace('<script src="config.js"></script>','<script>window.APP_CONFIG={};</script>')
html=html.replace('<script type="module" src="app.js"></script>','<script type="module">\n'+script.replace('</script','<\\/script')+'\n</script>')
(root/'demo.html').write_text(html)
print('Built demo.html')
