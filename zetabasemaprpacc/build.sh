#!/bin/bash

checkdocker
check4dockerimage "${APP_IMG_NAME}" BUILD

if [ "$BUILD" == "Y" ]; then
    rm -rf $BUILD_TMP
    mkdir -p $BUILD_TMP
    cd $BUILD_TMP

    dockerprox "DOCKER_LINE"

    # Since BUILD is now "Y" The vers file actually makes the dockerfile
    . ${MYDIR}/${APP_PKG_BASE}/${APP_VERS_FILE}

    sudo docker build -t $APP_IMG .
    sudo docker push $APP_IMG
    read -e -p "Do you wish to tag ${APP_IMG_NAME}:${APP_VER} as ${APP_IMG_NAME}:latest? (Y/N): " -i "Y" TAG_LATEST
    if [ "$TAG_LATEST" == "Y" ]; then
        sudo docker tag $APP_IMG ${ZETA_DOCKER_REG_URL}/${APP_IMG_NAME}:latest
    fi

    cd $MYDIR
    rm -rf $BUILD_TMP
    echo ""
    @go.log INFO "$APP_NAME package build with $APP_VERS_FILE"
    echo ""
else
    @go.log WARN "Not rebuilding $APP_NAME"
fi


