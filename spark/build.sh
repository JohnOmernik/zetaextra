#!/bin/bash

checkdocker

echo "Spark can use the default zetabase image, (as zetaspark) built here, or it can use an anaconda python base image (build in the anaconda package)"
read -e -p "Do you wish the build the zetaspark package based on zetabase (Answer no if you will use anaspark build elsewhere)? (Y/N): " -i "N" BUILD_ZETA_SPARK

if [ "$BUILD_ZETA_SPARK" == "Y" ]; then
    APP_IMG_NAME="zetaspark"
    APP_IMG="${ZETA_DOCKER_REG_URL}/${APP_IMG_NAME}:latest"
    check4dockerimage "${APP_IMG_NAME}" BUILD
    REQ_APP_IMG_NAME="zetabase"
    reqdockerimg "${REQ_APP_IMG_NAME}"
fi


if [ ! -f "${APP_PKG_DIR}/${APP_URL_FILE}" ]; then
    @go.log INFO "$APP_URL_FILE not found in APP_PKG_DIR - Downloading"
    wget ${APP_URL}
    echo "Moving $APP_URL_FILE to $APP_PKG_DIR"
    mv ${APP_URL_FILE} ${APP_PKG_DIR}/
fi

if [ "$BUILD" == "Y" ]; then
    rm -rf $BUILD_TMP
    mkdir -p $BUILD_TMP
    cd $BUILD_TMP

    # Since BUILD is now "Y" The vers file actually makes the dockerfile
    . ${MYDIR}/${APP_PKG_BASE}/${APP_VERS_FILE}

    sudo docker build -t $APP_IMG .
    sudo docker push $APP_IMG

    cd $MYDIR
    rm -rf $BUILD_TMP
    echo ""
    @go.log INFO "$APP_NAME package build with $APP_VERS_FILE"
    echo ""
else
    @go.log WARN "Not rebuilding $APP_NAME"
fi


