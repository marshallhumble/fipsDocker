This is a docker build that builds OpenSSL in fips 
mode and the build Python against it. 
 
The tests in the last stage verify that openSSL 
and Python are using fips 140-2 compliant modules. 

Based on the Filigran HQ image:

https://github.com/FiligranHQ/docker-python-nodejs-fips

