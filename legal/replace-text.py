import sys,argparse,pypandoc ,os
from tidylib import tidy_document

currentPath = os.path.dirname(os.path.realpath(__file__))

def convertDocxToHtml(fileName , **keywords):
   output = pypandoc.convert("%s/%s" %(currentPath, fileName), 'html')
   output, errors = tidy_document(output)

   for key in keywords:
      output = output.replace(key, keywords[key][0])

   with open("%s/%s.html" % (currentPath,fileName), "w") as docx_file:
      docx_file.write(output)

   print ("File Converted successfully" if not errors else errors)

def main():
   requirements = [
      'file-name',
      'company-address',
      'esop-sc-address',
      'options-per-share',
      'strike-price',
      'pool-options',
      'new-employee-pool-share',
      'employee-address',
      'issued-options',
      'employee-pool-options',
      'employee-extra-options',
      'issue-date',
      'vesting-period',
      'cliff-period',
      'bonus-options',
      'residual-amount',
      'time-to-sign',
      'curr-block-hash'
   ]

   parser = argparse.ArgumentParser()
   for req in requirements:
      parser.add_argument('--%s'%req, action='append')
   args = parser.parse_args()

   myDict = vars(args)
   for k,v in myDict.items():
      if v is None:
         print("%s required"%k)
         return
      if k not in requirements:
         print ("%s invalid argument"%k)

   fileName = myDict['file_name'][0]
   del myDict['file_name']
   convertDocxToHtml(fileName ,**myDict )

if __name__ == "__main__":
   main()
