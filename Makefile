
##

TARGET=annkedetect
HOSTNAME:=$(shell hostname)
CFG_SRC:=$(if $(wildcard $(TARGET).$(HOSTNAME).cfg),$(TARGET).$(HOSTNAME).cfg,$(TARGET).cfg)

# the detector: YOLOX-S trained on COCO, from the OpenCV model zoo (35 MB, so fetched rather than in the repo)
MODEL=models/yolox_s.onnx
MODEL_URL=https://huggingface.co/opencv/object_detection_yolox/resolve/main/object_detection_yolox_2022nov.onnx
MODEL_SHA256=c5c2d13e59ae883e6af3b45daea64af4833a4951c92d116ec270d9ddbe998063

##

all: check

$(MODEL):
	mkdir -p models
	curl -sSL --fail -o $@.part $(MODEL_URL)
	echo "$(MODEL_SHA256)  $@.part" | sha256sum -c --quiet
	mv $@.part $@
node_modules: package.json
	npm install --no-audit --no-fund --ignore-scripts
	touch node_modules
check: $(TARGET)
	node --check $(TARGET)
	@echo "syntax OK"
format:
	prettier --write $(TARGET)
# what clips would get, writing nothing: make test CLIP="/opt/storage/camera/side/<YYYYMMDD>/recording_<...>.mp4 ..."
test: $(TARGET) $(MODEL) node_modules
	./$(TARGET) $(CFG_SRC) --test $(CLIP)

.PHONY: all check format test

##

INSTALL=annkedetect
DIR_INSTALL=/usr/local/bin
DIR_LIB=/usr/local/lib/annkedetect
DIR_DEFAULT=/etc/default
DIR_SYSTEMD=/etc/systemd/system
define install_depend_systemd
	install -m 644 $(1).service $(DIR_SYSTEMD)/$(2).service
	systemctl daemon-reload
	systemctl enable $(2)
	systemctl start $(2) || echo "Warning: Failed to start $(2)"
endef
define install_service_systemd
	-systemctl stop $(2) 2>/dev/null || true
	install -m 644 $(1).service $(DIR_SYSTEMD)/$(2).service
	systemctl daemon-reload
	systemctl enable $(2)
	systemctl start $(2) || echo "Warning: Failed to start $(2)"
endef
# the tool, its one npm dependency and the model, in DIR_LIB; of ONNX Runtime's prebuilt binaries only
# linux/x64 is kept (the others are ~240 MB)
install_target: $(TARGET) $(MODEL) package.json package-lock.json
	install -d $(DIR_LIB)/models
	install -m 755 $(TARGET) $(DIR_LIB)/$(TARGET)
	install -m 644 package.json package-lock.json $(DIR_LIB)/
	install -m 644 $(MODEL) $(DIR_LIB)/$(MODEL)
	cd $(DIR_LIB) && npm ci --omit=dev --no-audit --no-fund --ignore-scripts
	rm -rf $(DIR_LIB)/node_modules/onnxruntime-node/bin/napi-v*/darwin $(DIR_LIB)/node_modules/onnxruntime-node/bin/napi-v*/win32 \
		$(DIR_LIB)/node_modules/onnxruntime-node/bin/napi-v*/linux/arm64
	ln -sf $(DIR_LIB)/$(TARGET) $(DIR_INSTALL)/$(INSTALL)
install_default: $(CFG_SRC)
	@echo "installing config from $(CFG_SRC)"
	install -m 644 $(CFG_SRC) $(DIR_DEFAULT)/$(INSTALL)
install_storage: $(TARGET)-storage.service
	$(call install_depend_systemd,$(TARGET)-storage,$(INSTALL)-storage)
install_service: $(TARGET).service
	$(call install_service_systemd,$(TARGET),$(INSTALL))
install: check install_target install_default install_storage install_service
restart:
	systemctl restart $(INSTALL)
status:
	@systemctl --no-pager --lines=0 status $(INSTALL) || true
	@journalctl -u $(INSTALL) -n 20 --no-pager -o cat
.PHONY: install install_target install_default install_storage install_service
.PHONY: restart status

##
