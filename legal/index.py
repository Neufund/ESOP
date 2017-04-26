from subprocess import call
import json,os

currentPath = os.path.dirname(os.path.realpath(__file__))
with open( 'config.json' , "r" ) as file:
    config = file.read()
config = json.loads(config)
with open( 'ipfs_tags.json' , "r" ) as file:
    keywords = file.read()
keywords = json.loads(keywords)

for fileName in config['files']:
    with open('%s/%s.html'%(currentPath,fileName) , "r" ) as file:
        data = file.read()

    for key in keywords:
        data = data.replace(key , keywords[key])

    with open('%s/%s-edited.html'%(currentPath, fileName) , "w" ) as file:
        file.write(data)
    print("File saved localy")

    cmd = "scp %s/%s-edited.html %s:%s"%(currentPath,fileName,config['ssh-user'],config['destination'])
    call(cmd.split(" "))

    print("File Uploaded remotely")

    cmd = 'ssh %s docker exec -i %s ipfs add /export/%s-edited.html'%(config['ssh-user'],config['docker'] , fileName)
    call(cmd.split(" "))

    print("Finished")
