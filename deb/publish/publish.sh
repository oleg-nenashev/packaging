#!/bin/bash -ex
bin="$(dirname $0)"

ssh $SSH_OPTS $PKGSERVER mkdir -p "'$DEBDIR/'"
rsync -avz -e "ssh $SSH_OPTS" "${DEB}" "$PKGSERVER:$(echo $DEBDIR | sed 's/ /\\ /g')/"

D=/tmp/$$
mkdir -p $D/binary $D/contents
cp -R "$bin/contents/." $D/contents
cp "${GPG_PUBLIC_KEY}" $D/contents/${ORGANIZATION}.key

# generate web index
"$bin/gen.rb" > $D/contents/index.html

"$BASE/bin/branding.py" $D


# build package index
# see http://wiki.debian.org/SecureApt for more details
cp "${DEB}" $D/binary
pushd $D
  apt-ftparchive packages binary > binary/Packages
  apt-ftparchive contents binary > binary/Contents
popd

# merge the result
pushd $D/binary
  mvn org.kohsuke:apt-ftparchive-merge:1.4:merge -Durl="$DEB_URL/binary/" -Dout=../merged
popd

cat $D/merged/Packages > $D/binary/Packages
cat $D/merged/Packages | gzip -9c > $D/binary/Packages.gz
cat $D/merged/Packages | bzip2 > $D/binary/Packages.bz2
cat $D/merged/Packages | lzma > $D/binary/Packages.lzma
cat $D/merged/Contents | gzip -9c > $D/binary/Contents.gz
apt-ftparchive -c $bin/release.conf release $D/binary > $D/binary/Release
# sign the release file
rm $D/binary/Release.gpg || true
gpg --batch --no-use-agent --no-default-keyring --digest-algo=sha256 --keyring "$GPG_KEYRING" --secret-keyring="$GPG_SECRET_KEYRING" --passphrase-file "$GPG_PASSPHRASE_FILE" \
  -abs -o $D/binary/Release.gpg $D/binary/Release

cp $D/binary/Packages.* $D/binary/Release $D/binary/Release.gpg $D/binary/Contents.gz $D/contents/binary

rsync -avz -e "ssh $SSH_OPTS" $D/contents/ "$PKGSERVER:$(echo $DEB_WEBDIR | sed 's/ /\\ /g')"

rm -rf $D
