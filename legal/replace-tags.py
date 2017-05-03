#!/usr/bin/env python

import sys,argparse,os,json,traceback
import sys
reload(sys)
sys.setdefaultencoding('utf8')

currentPath = os.path.dirname(os.path.realpath(__file__))

def replaceTags(fileName , output = None ,**tags):

   with open('%s/%s' % (currentPath, fileName), "r") as file:
      inputFile = file.read()

   for key in tags:
      inputFile = inputFile.replace('{%s}'%key, tags[key])

   if output:
      with open("%s/%s" % (currentPath,output), "w") as outputFile:
         outputFile.write(inputFile)

      print ("File Converted successfully" + '%s/%s' % (currentPath, output))
   else:
      print(inputFile)
import sys

class MyParser(argparse.ArgumentParser):
    def error(self, message):
        sys.stderr.write('error: %s\n' % message)
        self.print_help()
        sys.exit(2)


def main():
   requirements = [
      'input',
      'config',
   ]
   parser = MyParser()
   parser.add_argument('input', action='append', help='<html file name>')
   parser.add_argument('config', action='append', help='<json with tag replacement file name>')

   parser.add_argument('-o','--output', action='append')
   args = parser.parse_args()

   myDict = vars(args)
   fileName = myDict['input'][0]
   configFile = myDict['config'][0]
   output = myDict['output'][0] if 'output' in myDict and myDict['output'] != None else None

   fileChecking= None
   try:
      for r in requirements:
         fileChecking = myDict[r][0]
         assert os.path.isfile('%s/%s'%(currentPath,myDict[r][0]))

      with open('%s/%s' % (currentPath, configFile), "r") as file:
         tags = file.read()

      tags = json.loads(tags)
      replaceTags(fileName ,output , **tags)
   except AssertionError as e:
      print("An error occurred: %s file doesn't exist"%fileChecking)
   except Exception as e:
      _, _, tb = sys.exc_info()

      tb_info = traceback.extract_tb(tb)
      filename, line, func, text = tb_info[-1]

      print('An error occurred on line {} in statement {}'.format(line, text))


if __name__ == "__main__":
   main()
