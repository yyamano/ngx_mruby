#!/bin/sh

# Default install and test
#   download nginx into ./build/
#   build into ./build/nginx
#   test on ./build/nginx

set -e

. ./nginx_version

# OS specific configuration
if [ `uname -s` = "NetBSD" ]; then
    NPROCESSORS_ONLN="NPROCESSORS_ONLN"
    NGINX_DEFUALT_OPT='--with-debug --with-http_stub_status_module --with-http_ssl_module --with-ld-opt=-L/usr/pkg/lib\ -Wl,-R/usr/pkg/lib --with-cc-opt=-g\ -O0'
    MAKE=gmake
    KILLALL=pkill
    PS_C="pgrep -l"
else
    NPROCESSORS_ONLN="_NPROCESSORS_ONLN"
    NGINX_DEFUALT_OPT='--with-debug --with-http_stub_status_module --with-http_ssl_module --with-cc-opt=-g\ -O0\ -fsanitize=address\ -Wl,--no-undefined --with-ld-opt=-fsanitize=address'
    MAKE=make
    KILLALL=killall
    PS_C="ps -C"
fi

if [ -n "$BUILD_DYNAMIC_MODULE" ]; then
    BUILD_DIR='build_dynamic'
    NGINX_INSTALL_DIR=`pwd`'/build_dynamic/nginx'
else
    BUILD_DIR='build'
    NGINX_INSTALL_DIR=`pwd`'/build/nginx'
fi

if [ $NGINX_SRC_MINOR -eq 11 -a $NGINX_SRC_PATCH -ge 5 ]; then
    NGINX_CONFIG_OPT="--prefix=${NGINX_INSTALL_DIR} ${NGINX_DEFUALT_OPT} --with-stream"
elif [ $NGINX_SRC_MINOR -eq 11 -a $NGINX_SRC_PATCH -lt 5 ] || [ $NGINX_SRC_MINOR -eq 10 ] || [ $NGINX_SRC_MINOR -eq 9 -a $NGINX_SRC_PATCH -ge 6 ]; then
    NGINX_CONFIG_OPT="--prefix=${NGINX_INSTALL_DIR} ${NGINX_DEFUALT_OPT} --with-stream --without-stream_access_module"
else
    NGINX_CONFIG_OPT="--prefix=${NGINX_INSTALL_DIR} ${NGINX_DEFUALT_OPT}"
fi

if [ "$NUM_THREADS_ENV" != "" ]; then
    NUM_THREADS=$NUM_THREADS_ENV
else
    NUM_PROCESSORS=`getconf $NPROCESSORS_ONLN`
    if [ $NUM_PROCESSORS -gt 1 ]; then
        NUM_THREADS=$(expr $NUM_PROCESSORS / 2)
    else
        NUM_THREADS=1
    fi
fi

echo "NGINX_CONFIG_OPT=$NGINX_CONFIG_OPT"
echo "NUM_THREADS=$NUM_THREADS"

export NGX_MRUBY_CFLAGS=-DMRB_GC_STRESS

if [ "$ONLY_BUILD_NGX_MRUBY" = "" ]; then

  echo "nginx Downloading ..."
  if [ -d "./${BUILD_DIR}" ]; then
      echo "build directory was found"
  else
      mkdir ${BUILD_DIR}
  fi
  cd ${BUILD_DIR}
  if [ ! -e ${NGINX_SRC_VER} ]; then
      wget http://nginx.org/download/${NGINX_SRC_VER}.tar.gz
      echo "nginx Downloading ... Done"
      tar xzf ${NGINX_SRC_VER}.tar.gz
  fi
  ln -snf ${NGINX_SRC_VER} nginx_src
  NGINX_SRC=`pwd`'/nginx_src'
  cd ..

  echo "ngx_mruby configure ..."
  ./configure --with-ngx-src-root=${NGINX_SRC} --with-ngx-config-opt="${NGINX_CONFIG_OPT}" $@
  echo "ngx_mruby configure ... Done"

  if [ -n "$BUILD_DYNAMIC_MODULE" ]; then
      echo "mruby building for suppot dynamic module ..."
      $MAKE build_mruby_with_fpic NUM_THREADS=$NUM_THREADS -j $NUM_THREADS
      echo "mruby building for suppot dynamic module ... Done"

      echo "ngx_mruby building as dynamic module ..."
      $MAKE ngx_mruby_dynamic NUM_THREADS=$NUM_THREADS -j $NUM_THREADS
  else
      echo "mruby building ..."
      $MAKE build_mruby NUM_THREADS=$NUM_THREADS -j $NUM_THREADS
      echo "mruby building ... Done"

      echo "ngx_mruby building ..."
      $MAKE NUM_THREADS=$NUM_THREADS -j $NUM_THREADS
  fi
else
  $MAKE make_ngx_mruby NUM_THREADS=$NUM_THREADS -j $NUM_THREADS
fi

echo "ngx_mruby building ... Done"

echo "ngx_mruby testing ..."
$MAKE install
$PS_C nginx && $KILLALL nginx
sed -e "s|__NGXDOCROOT__|${NGINX_INSTALL_DIR}/html/|g" test/conf/nginx.conf > ${NGINX_INSTALL_DIR}/conf/nginx.conf
cd ${NGINX_INSTALL_DIR}/html && sh -c 'yes "" | openssl req -new -days 365 -x509 -nodes -keyout localhost.key -out localhost.crt' && sh -c 'yes "" | openssl req -new -days 1 -x509 -nodes -keyout dummy.key -out dummy.crt' && cd -

if [ $NGINX_SRC_MINOR -ge 10 ] || [ $NGINX_SRC_MINOR -eq 9 -a $NGINX_SRC_PATCH -ge 6 ]; then
  cat test/conf/nginx.stream.conf >> ${NGINX_INSTALL_DIR}/conf/nginx.conf
fi

if [ -n "$BUILD_DYNAMIC_MODULE" ]; then
    sed -e "s|build/nginx|build_dynamic/nginx|g" ${NGINX_INSTALL_DIR}/conf/nginx.conf | tee ${NGINX_INSTALL_DIR}/conf/nginx.conf.tmp
    echo "load_module modules/ngx_http_mruby_module.so;" > ${NGINX_INSTALL_DIR}/conf/nginx.conf
    cat ${NGINX_INSTALL_DIR}/conf/nginx.conf.tmp >> ${NGINX_INSTALL_DIR}/conf/nginx.conf
fi

cp -pr test/html/* ${NGINX_INSTALL_DIR}/html/.
sed -e "s|__NGXDOCROOT__|${NGINX_INSTALL_DIR}/html/|g" test/html/set_ssl_cert_and_key.rb > ${NGINX_INSTALL_DIR}/html/set_ssl_cert_and_key.rb

echo "====================================="
echo ""
echo "ngx_mruby starting and logging"
echo ""
echo "====================================="
echo ""
echo ""
${NGINX_INSTALL_DIR}/sbin/nginx &
echo ""
echo ""
sleep 2 # waiting for nginx
#cd mruby
#./build/test/bin/mruby ../test/t/ngx_mruby.rb
./mruby/build/test/bin/mruby ./test/t/ngx_mruby.rb
$KILLALL nginx
echo "ngx_mruby testing ... Done"

echo "test.sh ... successful"
