#!/system/bin/sh

if [ "$#" == 0 ];then
	echo "Usage: $0 <original boot.img> [eng|user]"
	exit 1
fi

set -e

if [ -f "$2" ];then
	scr="$(readlink -f "$2")"
	used_scr=1
else
	scr="$PWD/changes.sh"
fi

function cleanup() {
	rm -Rf "$bootimg_extract" "$d2"
}

trap cleanup EXIT


function startBootImgEdit() {
	f="$(readlink -f "$1")"
	homedir="$PWD"
	scriptdir="$(dirname "$(readlink -f "$0")")"
	bootimg_extract="$(mktemp -d)"
	cd "$bootimg_extract"

	"$scriptdir/bin/bootimg-extract" "$f"
	d2="$(mktemp -d)"
	cd "$d2"

	if [ -f "$bootimg_extract"/ramdisk.gz ];then
		gunzip -c < "$bootimg_extract"/ramdisk.gz |cpio -i
		gunzip -c < "$bootimg_extract"/ramdisk.gz > ramdisk1
	else
		echo "Unknown ramdisk format"
		cd "$homedir"
		rm -Rf "$bootimg_extract" "$d2"
		exit 1
	fi

	INITRAMFS_FILES=""
}

function addFile() {
	#WARNING FIXME: If you want to add toto and toto2
	#You must add toto2 THEN toto
	[[ "$INITRAMFS_FILES" =~ "$1" ]] || INITRAMFS_FILES="$INITRAMFS_FILES $*"
}

function doneBootImgEdit() {
	#List of files to replace \n separated
	echo $INITRAMFS_FILES |tr ' ' '\n' | cpio -o -H newc > ramdisk2

	if [ -f "$bootimg_extract"/ramdisk.gz ];then
		#TODO: Why can't I recreate initramfs from scratch?
		#Instead I use the append method. files gets overwritten by the last version if they appear twice
		#Hence sepolicy/su/init.rc are our version
		cat ramdisk1 ramdisk2 |gzip -9 -c > "$bootimg_extract"/ramdisk.gz
	fi

	cd "$bootimg_extract"
	rm -Rf "$d2"
	"$scriptdir/bin/bootimg-repack" "$f"
	cp new-boot.img "$homedir"

	cd "$homedir"
	rm -Rf "$bootimg_extract"
}

#allow <list of scontext> <list of tcontext> <class> <list of perm>
function allow() {
	addFile sepolicy
	for s in $1;do
		for t in $2;do
			for p in $4;do
				"$scriptdir"/bin/sepolicy-inject -s $s -t $t -c $3 -p $p -P sepolicy
			done
		done
	done
}

function noaudit() {
	addFile sepolicy
	for s in $1;do
		for t in $2;do
			for p in $4;do
				"$scriptdir"/bin/sepolicy-inject -s $s -t $t -c $3 -p $p -P sepolicy
			done
		done
	done
}

startBootImgEdit "$1"

shift
[ -n "$used_scr" ] && shift

. $scr

doneBootImgEdit
if [ -f $scriptdir/keystore.x509.pem -a -f $scriptdir/keystore.pk8 ];then
	java -jar $scriptdir/keystore_tools/BootSignature.jar /boot new-boot.img $scriptdir/keystore.pk8 $scriptdir/keystore.x509.pem new-boot.img.signed
fi
