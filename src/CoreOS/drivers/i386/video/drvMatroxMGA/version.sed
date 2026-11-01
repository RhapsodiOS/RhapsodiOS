#!/bin/sh

if [ "$1" = "" ]; then
	echo "Usage: version.sed version-number";
	exit;
fi

VERS=`cat version`
echo $VERS
FILES=`find . -name \*.table -print`
for file in $FILES; do
  echo Updating $file ;
  rm -f tmp-edit-file tmp-edit-file1
  sed -e 's,"MatroxMGA '$VERS'","MatroxMGA '$1'",' $file > tmp-edit-file1 ;
  sed -e 's,"'$VERS'","'$1'",' tmp-edit-file1 > tmp-edit-file ;
  mv tmp-edit-file $file ;
done

echo $1 > version
echo -n #define MGA_VERSION_STRING \"MatroxMGA Driver v$1\\ > version.h
echo n\" >> version.h
