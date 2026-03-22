        const RADIO_SERVICE_UUID = "00001100-d102-11e1-9b23-00025b00a5a5";
        const RADIO_WRITE_UUID = "00001101-d102-11e1-9b23-00025b00a5a5";
        const RADIO_INDICATE_UUID = "00001102-d102-11e1-9b23-00025b00a5a5";

        var websocketMode = false;
        var websocket = null;
        var bluetoothDevice = null;
        var radioService = null;
        var writeCharacteristic = null;
        var indicateCharacteristic = null;
        var gattServer = null;

        var radioDevInfo = null;
        var radioHtStatus = null;
        var radioChannels = null;
        var radioSettings = null;

        const aprsDiv = document.getElementById('aprs');
        const statusDiv = document.getElementById('status');
        const terminalDiv = document.getElementById('terminal');
        const tabTwoButton = document.getElementById('tab2-icon');
        const leftColumnConnectButton = document.getElementById('leftColumnConnectButton');

        // Radio panel
        const leftColumnDiv = document.getElementById('leftColumn');
        const radioStatusDiv = document.getElementById('radioStatus');
        const rssiDiv = document.getElementById('rssi2');
        const radioChannelsDiv = document.getElementById('radioChannels');
        const radiovfo1 = document.getElementById('radiovfo1');
        const radiovfo1a = document.getElementById('radiovfo1a');
        const radiovfo1b = document.getElementById('radiovfo1b');
        const radiovfoline = document.getElementById('radiovfoline');
        const radiovfo2 = document.getElementById('radiovfo2');
        const radiovfo2a = document.getElementById('radiovfo2a');
        const radiovfo2b = document.getElementById('radiovfo2b');

        // Get menu bar elements
        const menuConnect = document.getElementById('menuConnect');
        const menuDisconnect = document.getElementById('menuDisconnect');
        const sendCommandModal = new bootstrap.Modal(document.getElementById('sendCommandModal'));
        const modalCommandInput = document.getElementById('modalCommandInput');
        const modalSendCommandButton = document.getElementById('modalSendCommandButton');
        const menuSendCommand = document.getElementById('menuSendCommand'); // Reference to the new menu item

        // NEW: Get APRS input elements
        const aprsMessageInput = document.getElementById('aprsMessageInput');
        const sendAprsButton = document.getElementById('sendAprsButton');

        // Leaflet Map variable
        let mymap = null;
        const mapTabButton = document.getElementById('tab_map-icon');

        // NEW: Packet Tab Elements
        const packetListContainer = document.querySelector('.packet-list-container');
        const packetDetailsContainer = document.querySelector('.packet-details-container');
        const resizer = document.querySelector('.resizer');
        const packetList = document.getElementById('packetList');
        const packetDetails = document.getElementById('packetDetails');
        let packets = []; // Array to store packet objects

        aprsData("KK7VZT-6", "This is sample text1", "inbound");
        aprsData("KK7VZT-7", "This is sample text2 This is sample text2 This is sample text2 This is sample text2 This is sample text2 This is sample text2 This is sample text2 This is sample text2 This is sample text2 This is sample text2 This is sample text2 This is sample text2x", "outbound");
        aprsData("KK7VZT-6", "This is sample text1", "inbound");
        aprsData("KK7VZT-5", "This is sample text1", "inbound");

        terminalData(null, "Connecting...", "status");
        terminalData("KK7VZT-6", "This is sample text1", "inbound");
        terminalData("KK7VZT-7", "This is sample text2", "outbound");
        terminalData("KK7VZT-6", "This is sample text3", "inbound");
        terminalData("KK7VZT-7", "This is sample text4", "outbound");
        terminalData(null, "Disconnected.", "status");

        var lastOutBoundAprsCallsign = null;
        function aprsData(callsign, message, type = 'status') {
            if ((callsign != null) && (type == "inbound") && (lastOutBoundAprsCallsign != callsign)) {
                lastOutBoundAprsCallsign = callsign;
                const ecallsign = document.createElement('div');
                ecallsign.className = 'aprs-in-callsign';
                if (type === 'outbound') { ecallsign.className = 'aprs-out-callsign'; }
                ecallsign.textContent = callsign;
                aprsDiv.insertBefore(ecallsign, aprsDiv.firstChild);
            }
            const entry = document.createElement('div');
            entry.className = 'aprs-in-entry';
            if (type === 'outbound') { entry.className = 'aprs-out-entry'; }
            entry.textContent = `${message}`;
            aprsDiv.insertBefore(entry, aprsDiv.firstChild);
            aprsDiv.scrollTop = aprsDiv.scrollHeight; // Auto-scroll
        }

        function terminalData(callsign, message, type = 'status') {
            const entry = document.createElement('p');
            let textColorClass = 'text-white'; // Default for 'info'
            if (type === 'status') {
                textColorClass = 'text-warning fw-bold';
            } else if (type === 'outbound') {
                textColorClass = 'text-light fw-bold';
            }
            entry.className = `log-entry ${textColorClass} mb-0`; // mb-0 for no margin-bottom
            entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
            //console.log(terminalDiv.childElementCount);
            terminalDiv.insertBefore(entry, terminalDiv.firstChild);
            terminalDiv.scrollTop = statusDiv.scrollHeight; // Auto-scroll
        }

        function log(message, type = 'info') {
            const entry = document.createElement('p');
            let textColorClass = 'text-dark'; // Default for 'info'
            if (type === 'error') {
                textColorClass = 'text-danger fw-bold';
            } else if (type === 'success') {
                textColorClass = 'text-success fw-bold';
            } else if (type === 'data') {
                textColorClass = 'text-secondary fst-italic';
            }
            entry.className = `log-entry ${textColorClass} mb-0`; // mb-0 for no margin-bottom
            entry.textContent = `[${new Date().toLocaleTimeString()}] ${message}`;
            statusDiv.insertBefore(entry, statusDiv.firstChild);
            statusDiv.scrollTop = statusDiv.scrollHeight; // Auto-scroll
            //console.log(`[${type.toUpperCase()}] ${message}`);
        }

        function clearLogs() {
            statusDiv.innerHTML = '';
        }

        function hexStringToUint8Array(hexString) {
            if (hexString.length % 2 !== 0) {
                log("Hex string must have an even number of digits.", 'error');
                throw new Error("Hex string must have an even number of digits.");
            }
            const byteArray = new Uint8Array(hexString.length / 2);
            for (let i = 0; i < byteArray.length; i++) {
                byteArray[i] = parseInt(hexString.substr(i * 2, 2), 16);
            }
            return byteArray;
        }

        function arrayBufferToHexString(buffer) {
            return Array.prototype.map.call(new Uint8Array(buffer), x => ('00' + x.toString(16)).slice(-2)).join('');
        }

        function setupWebSocket() {
            websocket = new WebSocket("/websocket.aspx");
            websocket.binaryType = "arraybuffer";
            websocket.onerror = (event) => { log('Websocket error', 'error'); onDisconnected(); websocket = null; };
            websocket.onopen = (event) => { log('Websocket connected', 'success'); };
            websocket.onclose = (event) => {
                log('Websocket closed', 'success');
                websocket = null;
                radioStatusDiv.textContent = 'Websocket...';
                menuConnect.classList.add('disabled');
                menuDisconnect.classList.add('disabled');
                leftColumnConnectButton.style.display = 'none'; // Hide when connecting/connected
                setTimeout(setupWebSocket, 5000);
            };
            websocket.onmessage = (event) => {
                //log('Websocket message: ' + JSON.stringify(event.data), 'success');
                if (typeof event.data === 'string') {
                    if (event.data.startsWith("log:")) {
                        log(event.data.substring(4), 'success');
                    }
                    if (event.data == "disconnected") { onDisconnected(); }
                    if (event.data == "connecting") {
                        // Update button states
                        menuConnect.classList.add('disabled');
                        leftColumnConnectButton.style.display = 'none'; // Hide when connecting/connected
                        menuSendCommand.classList.add('disabled'); // Disable send command option during connection setup
                        sendAprsButton.disabled = true; // Disable APRS send button during connection setup
                        radioStatusDiv.textContent = 'Connecting...';
                    }
                    if ((event.data == "connected") || (event.data == "wasconnected")) {
                        radioStatusDiv.textContent = 'Connecting...';
                        menuConnect.classList.add('disabled');
                        leftColumnConnectButton.style.display = 'none'; // Hide when connecting/connected
                        menuSendCommand.classList.add('disabled'); // Disable send command option during connection setup
                        sendAprsButton.disabled = true; // Disable APRS send button during connection setup
                        menuDisconnect.classList.remove('disabled');
                        modalSendCommandButton.disabled = false; // Enable modal send command button
                        menuSendCommand.classList.remove('disabled'); // Enable send command option in menu
                        sendAprsButton.disabled = false; // Enable APRS send button on successful connection
                        radioChannelsDiv.style.display = 'flex';
                        log('Device connected and ready.', 'success');

                        if (event.data == "wasconnected") {
                            // Send commands to subscribe to events & get initial state
                            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_DEV_INFO, 3);
                            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_SETTINGS, null);
                            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_HT_STATUS, null);
                        }
                    }
                } else { // This is binary data
                    handleNotificationsEx(new Uint8Array(event.data));
                }
            };
        }

        // Centralized connect/disconnect logic to be called from both buttons and menu
        async function initiateConnect() {
            clearLogs();

            // in websocket mode, just send the connect command
            if (websocketMode) { websocket.send('connect'); return; }

            if (!navigator.bluetooth) {
                log('Web Bluetooth API is not available in this browser!', 'error');
                return;
            }

            try {
                log('Requesting Bluetooth Device...');
                bluetoothDevice = await navigator.bluetooth.requestDevice({
                    filters: [{ name: 'UV-PRO' }],
                    optionalServices: [RADIO_SERVICE_UUID]
                });

                log(`Device selected: ${bluetoothDevice.name || bluetoothDevice.id}`, 'success');
                bluetoothDevice.addEventListener('gattserverdisconnected', onDisconnected);

                // Update button states
                menuConnect.classList.add('disabled');
                leftColumnConnectButton.style.display = 'none'; // Hide when connecting/connected
                menuSendCommand.classList.add('disabled'); // NEW: Disable send command option during connection setup
                sendAprsButton.disabled = true; // Disable APRS send button during connection setup
                radioStatusDiv.textContent = 'Connecting...';

                log('Connecting to GATT Server...');
                gattServer = await bluetoothDevice.gatt.connect();
                log('Connected to GATT Server.', 'success');

                // *** CRITICAL CHANGE: Introduce a small delay here ***
                // This gives the Android Bluetooth stack and the peripheral a moment to settle.
                log('Waiting briefly for GATT services to stabilize...');
                await new Promise(resolve => setTimeout(resolve, 500)); // Wait for 500ms (adjust as needed)

                log(`Getting Radio Service (UUID: ${RADIO_SERVICE_UUID})...`);
                radioService = await gattServer.getPrimaryService(RADIO_SERVICE_UUID);
                log('Radio Service obtained.', 'success');

                log(`Getting Write Characteristic (UUID: ${RADIO_WRITE_UUID})...`);
                writeCharacteristic = await radioService.getCharacteristic(RADIO_WRITE_UUID);
                log('Write Characteristic obtained.', 'success');

                log(`Getting Indicate Characteristic (UUID: ${RADIO_INDICATE_UUID})...`);
                indicateCharacteristic = await radioService.getCharacteristic(RADIO_INDICATE_UUID);
                log('Indicate Characteristic obtained.', 'success');

                log('Starting notifications for Indicate Characteristic...');
                await indicateCharacteristic.startNotifications();
                indicateCharacteristic.addEventListener('characteristicvaluechanged', handleNotifications);
                log('Notifications started.', 'success');

                menuDisconnect.classList.remove('disabled');
                modalSendCommandButton.disabled = false; // NEW: Enable modal send command button
                menuSendCommand.classList.remove('disabled'); // NEW: Enable send command option in menu
                sendAprsButton.disabled = false; // Enable APRS send button on successful connection
                radioChannelsDiv.style.display = 'flex';
                log('Device connected and ready.', 'success');

                // Send commands to subscribe to events & get initial state
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_DEV_INFO, 3);
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_SETTINGS, null);
                SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.GET_HT_STATUS, null);
            } catch (error) {
                log(`Error: ${error.message}`, 'error');
                if (error.name === "NotFoundError") {
                    log("No device matching the specified service UUID was found. Ensure the device is powered on and advertising.", "error");
                }
                console.error('Connection failed:', error);
                menuConnect.classList.remove('disabled');
                menuDisconnect.classList.add('disabled');
                modalSendCommandButton.disabled = true; // NEW: Disable modal send command button
                menuSendCommand.classList.add('disabled'); // NEW: Disable send command option in menu
                sendAprsButton.disabled = true; // Disable APRS send button on connection error
                leftColumnConnectButton.style.display = 'block'; // Show on disconnection/error
            }
        }

        const bluetoothCommandQueue = new BluetoothCommandQueue();

        function writeToCharacteristic(data) {
            //log(`writeToCharacteristic: ${arrayBufferToHexString(data)}`, 'data');
            if (websocketMode) {
                const buffer = new Uint8Array(data).buffer;
                websocket.send(buffer);
            } else {
                return bluetoothCommandQueue.enqueue(() => {
                    const buffer = new Uint8Array(data).buffer;
                    return writeCharacteristic.writeValueWithResponse(buffer);
                });
            }
        }

        function SendCommand(group, cmd, data)
        {
            if ((typeof data == 'object') && (data != null)) {
                var header = new Uint8Array([0, group, 0, cmd]);
                writeToCharacteristic(Uint8Array.from([...header, ...data]));
            } else {
                writeToCharacteristic(new Uint8Array([0, group, 0, cmd, data]));
            }
        }

        async function initiateDisconnect() {
            // in websocket mode, just send the disconnect command
            if (websocketMode) {
                websocket.send('disconnect'); return;
            }

            if (!bluetoothDevice || !bluetoothDevice.gatt.connected) {
                log('Device not connected.', 'info');
                return;
            }
            try {
                log('Disconnecting from device...');
                await bluetoothDevice.gatt.disconnect();
                // onDisconnected will be called automatically
            } catch (error) {
                log(`Error during disconnection: ${error.message}`, 'error');
            }
        }

        leftColumnConnectButton.addEventListener('click', initiateConnect);

        // Menu bar event listeners
        menuConnect.addEventListener('click', (event) => {
            if (menuConnect.classList.contains('disabled')) {
                event.preventDefault();
            } else {
                initiateConnect();
            }
        });

        menuDisconnect.addEventListener('click', (event) => {
            if (menuDisconnect.classList.contains('disabled')) {
                event.preventDefault();
            } else {
                initiateDisconnect();
            }
        });

        // Disconnect
        function onDisconnected() {
            log('Device disconnected.', 'info');
            menuConnect.classList.remove('disabled');
            menuDisconnect.classList.add('disabled');
            modalSendCommandButton.disabled = true; // NEW: Disable modal send command button
            menuSendCommand.classList.add('disabled'); // NEW: Disable send command option in menu
            sendAprsButton.disabled = true; // Disable APRS send button on disconnect
            leftColumnConnectButton.style.display = 'block';
            rssiDiv.style['width'] = '0%';
            radiovfo1.textContent = radiovfo1a.textContent = radiovfo1b.textContent = '';
            radiovfo2.textContent = radiovfo2a.textContent = radiovfo2b.textContent = '';
            radiovfoline.style.display = 'none';
            radioStatusDiv.textContent = 'Disconnected';
            radioChannelsDiv.style.display = 'none';
            radioChannelsDiv.innerHTML = null;

            if (indicateCharacteristic) {
                indicateCharacteristic.removeEventListener('characteristicvaluechanged', handleNotifications);
            }

            bluetoothDevice = null;
            radioService = null;
            writeCharacteristic = null;
            indicateCharacteristic = null;
            gattServer = null;

            radioDevInfo = null;
            radioHtStatus = null;
            radioChannels = null;
            radioSettings = null;
        }

        function handleNotifications(event) {
            const value = event.target.value; // This is a DataView
            const receivedData = new Uint8Array(value.buffer)
            handleNotificationsEx(receivedData);
        }

        function handleNotificationsEx(receivedData) {
            const group = (receivedData[0] << 8) + receivedData[1];
            const cmd = ((receivedData[2] & 0x7F) << 8) + receivedData[3];
            switch (group) {
                case RadioCommandGroup.BASIC:
                    switch (cmd) {
                        case RadioBasicCommand.GET_DEV_INFO:
                            radioDevInfo = new RadioDevInfo(receivedData);
                            log(`Firmware: ${radioDevInfo.soft_ver_str}`);
                            log(`Channel count: ${radioDevInfo.channel_count}`);
                            radioChannels = Array(radioDevInfo.channel_count);
                            //SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.REGISTER_NOTIFICATION, 1);
                            // Fetch all channels
                            for (var i = 0; i < radioDevInfo.channel_count; i++) { SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.READ_RF_CH, i); }
                            break;
                        case RadioBasicCommand.READ_RF_CH:
                            var channel = new RadioChannelInfo(receivedData);
                            radioChannels[channel.channel_id] = channel;
                            if (channel.channel_id == (radioDevInfo.channel_count - 1)) { updateChannels(); }
                            updateRadioDisplay();
                            break;
                        case RadioBasicCommand.READ_SETTINGS:
                            log(`Settings`);
                            radioSettings = new RadioSettings(receivedData);
                            updateRadioDisplay();
                            break;
                        case RadioBasicCommand.GET_HT_STATUS:
                            log(`GET_HT_STATUS`);
                            radioHtStatus = new RadioHtStatus(receivedData);
                            rssiDiv.style['width'] = ((radioHtStatus.rssi * 100) / 15) + '%'; // Change RSSI bar
                            updateRadioDisplay();
                            break;
                        case RadioBasicCommand.EVENT_NOTIFICATION:
                            switch (receivedData[4]) {
                                case RadioNotification.HT_STATUS_CHANGED:
                                    log(`HTStatus`);
                                    radioHtStatus = new RadioHtStatus(receivedData);
                                    rssiDiv.style['width'] = ((radioHtStatus.rssi * 100) / 15) + '%'; // Change RSSI bar
                                    updateRadioDisplay();
                                    break;
                                case RadioNotification.HT_SETTINGS_CHANGED:
                                    radioSettings = new RadioSettings(receivedData);
                                    updateRadioDisplay();
                                    break;
                                default:
                                    log(`Unknown Event: ${receivedData[4]}`, 'data');
                                    break;
                            }
                            break;
                        case RadioBasicCommand.WRITE_SETTINGS:
                            if (receivedData[4] != 0) { log("WRITE_SETTINGS ERROR: " + receivedData[4], 'error'); }
                            break;
                        default:
                            log(`Group: ${group}, Cmd: ${cmd}`);
                            log(`Notification received: ${arrayBufferToHexString(receivedData)}`, 'data');
                            break;
                    }
                    break;
                case RadioCommandGroup.EXTENDED:
                    log(`Group: ${group}, Cmd: ${cmd}`);
                    log(`Notification received: ${arrayBufferToHexString(receivedData)}`, 'data');
                    break;
            }

            // TODO: Implement your protocol's message parsing here
            // e.g., const radioMessage = radio_message_from_protocol_js(new Uint8Array(receivedData));
            // log(`Parsed message: ${JSON.stringify(radioMessage)}`);
        }

        function escapeHtml(str) {
            var div = document.createElement('div');
            div.textContent = str;
            return div.innerHTML;
        }

        function updateChannels() {
            var html = '', channelCount = 0;
            radioStatusDiv.textContent = '';
            radiovfoline.style.display = '';
            for (var i = 0; i < radioChannels.length; i++) {
                var channel = radioChannels[i];
                var channelName = channel.name_str;
                if ((channelName == "") || (channelName == null)) {
                    channelName = null;
                    //channelName = "Channel " + (channel.channel_id + 1);
                }
                if (channelName != null) {
                    html += `<div id="channel${i}" onclick="selectChannel(${i})" class="channelBox">${escapeHtml(channelName)}</div>`;
                    channelCount++;
                }
            }
            radioChannelsDiv.innerHTML = html;
            //radioChannelsDiv.style.height = channelBoxMaxHeight;
        }

        function updateRadioDisplay() {
            //log(`updateRadioDisplay ${radioStatusDiv.textContent != ''}, ${radioHtStatus == null}, ${radioSettings == null}`);
            if ((radioStatusDiv.textContent != '') || (radioHtStatus == null) || (radioSettings == null)) {
                radiovfo1.textContent = radiovfo1a.textContent = radiovfo1b.textContent = '';
                radiovfo2.textContent = radiovfo2a.textContent = radiovfo2b.textContent = '';
                return;
            }
            radioChannelsDiv.style.display = 'absolute';

            var c1 = radioChannels[radioSettings.channel_a];
            var c2 = radioChannels[radioSettings.channel_b];
            if (radioSettings.scan) { c2 = radioChannels[radioHtStatus.curr_ch_id]; }

            if (c1.name_str != "") {
                radiovfo1.textContent = c1.name_str;
                radiovfo1a.textContent = (c1.rx_freq / 1000000).toFixed(3) + " MHz";
            } else {
                radiovfo1.textContent = "Empty";
                radiovfo1a.textContent = "";
            }

            if ((radioSettings.double_channel == 1) || (radioSettings.scan)) {
                radiovfo2.textContent = c2.name_str;
                radiovfo2a.textContent = (c2.rx_freq / 1000000).toFixed(3) + " MHz";
            } else {
                radiovfo2.textContent = "";
                radiovfo2a.textContent = "";
            }

            radiovfo2b.textContent = (radioSettings.scan) ? "Scanning..." : "";

            if (radioSettings.double_channel == 1) {
                if ((radioHtStatus.is_in_rx || radioHtStatus.is_in_tx) && (radioHtStatus.curr_ch_id == radioSettings.channel_id)) {
                    radiovfo1.style['color'] = radiovfo1a.style['color'] = 'lightgray';
                    radiovfo2.style['color'] = radiovfo2a.style['color'] = '#FA8072';
                } else {
                    radiovfo1.style['color'] = radiovfo1a.style['color'] = '#FA8072';
                    radiovfo2.style['color'] = radiovfo2a.style['color'] = 'lightgray';
                }
            } else {
                radiovfo1.style['color'] = radiovfo1a.style['color'] = 'lightgray';
                radiovfo2.style['color'] = radiovfo2a.style['color'] = 'lightgray';
            }

            for (var i = 0; i < radioChannels.length; i++) {
                var channelDiv = document.getElementById(`channel${i}`);
                if (channelDiv) {
                    channelDiv.style['background-color'] = ((i == radioSettings.channel_a) || ((radioSettings.double_channel == 1) && (i == radioSettings.channel_b))) ? '#EEE8AA' : '';
                }
            }
        }

        function selectChannel(c) {
            //log(`Select Channel: ${c}`);
            var data = radioSettings.ToByteArray(c, radioSettings.channel_b, radioSettings.double_channel, radioSettings.scan, radioSettings.squelch_level);
            SendCommand(RadioCommandGroup.BASIC, RadioBasicCommand.WRITE_SETTINGS, data);
        }

        // NEW: Event listener for the modal's send command button
        modalSendCommandButton.addEventListener('click', async () => {
            if (!writeCharacteristic) {
                log('Write characteristic not available.', 'error');
                return;
            }
            const hexCommand = modalCommandInput.value.trim().replace(/\s/g, ''); // remove spaces
            if (!hexCommand) {
                log('Command input is empty.', 'error');
                return;
            }

            try {
                const dataToSend = hexStringToUint8Array(hexCommand);
                log(`Sending command (hex): ${hexCommand}`, 'info');
                // log(`Sending command (bytes): ${dataToSend}`);

                await writeCharacteristic.writeValueWithResponse(dataToSend); // Or writeValueWithoutResponse
                log('Command sent successfully.', 'success');
                sendCommandModal.hide(); // Hide the modal after sending
                modalCommandInput.value = ''; // Clear the input after sending
            } catch (error) {
                log(`Error sending command: ${error.message}`, 'error');
                console.error('Send command error:', error);
            }
        });

        // NEW: Event listener for the APRS send button
        sendAprsButton.addEventListener('click', async () => {
            if (!writeCharacteristic) {
                log('Write characteristic not available. Connect to send APRS messages.', 'error');
                return;
            }
            const aprsMessage = aprsMessageInput.value.trim();
            if (!aprsMessage) {
                log('APRS message input is empty.', 'error');
                return;
            }

            try {
                // Here, you would convert your APRS message into the appropriate hex command
                // This is a placeholder for your specific radio's APRS message format.
                // For demonstration, let's just log the message as if it were sent.
                log(`Attempting to send APRS message: "${aprsMessage}"`, 'info');
                // Replace this with actual Bluetooth write operation:
                // const aprsCommandBytes = convertAprsMessageToBytes(aprsMessage);
                // await writeCharacteristic.writeValueWithResponse(aprsCommandBytes);

                aprsData("YOU", aprsMessage, "outbound"); // Simulate sending and add to chat
                log('APRS message simulated sent.', 'success');
                aprsMessageInput.value = ''; // Clear the input after sending

            } catch (error) {
                log(`Error sending APRS message: ${error.message}`, 'error');
                console.error('Send APRS message error:', error);
            }
        });

        // Leaflet Map Initialization
        function initializeMap() {
            if (mymap !== null) {
                // If map already exists, invalidate its size to re-render
                mymap.invalidateSize();
                return;
            }
            // Use Tualatin, Oregon coordinates as the default view
            mymap = L.map('mapid').setView([45.385, -122.753], 13); // Latitude, Longitude, Zoom level

            L.tileLayer('https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png', {
                attribution: '&copy; <a href="https://www.openstreetmap.org/copyright">OpenStreetMap</a> contributors'
            }).addTo(mymap);

            // Example marker
            L.marker([45.385, -122.753]).addTo(mymap)
                .bindPopup('Tualatin, Oregon (Initial Location)')
                .openPopup();
        }

        // Event listener for when the Map tab is shown
        mapTabButton.addEventListener('shown.bs.tab', function (event) {
            initializeMap();
        });


        // NEW: Packet Tab JavaScript
        function addPacket(time, summary, details) {
            const packetIndex = packets.length;
            packets.push({ time, summary, details });

            const listItem = document.createElement('li');
            listItem.textContent = `${time} - ${summary}`;
            listItem.setAttribute('data-index', packetIndex);
            listItem.addEventListener('click', () => {
                // Remove active class from previous item
                const currentActive = packetList.querySelector('li.active');
                if (currentActive) {
                    currentActive.classList.remove('active');
                }
                // Add active class to clicked item
                listItem.classList.add('active');
                packetDetails.textContent = packets[packetIndex].details;
            });
            packetList.prepend(listItem); // Add new packets at the top
        }

        // Sample packets
        addPacket(new Date().toLocaleTimeString(), "Packet 1: Position Report", "Detailed info for Packet 1: \n- Lat: 45.385\n- Lon: -122.753\n- Speed: 0 mph\n- Course: 0\n- Symbol: /O\n- Comment: Home QTH\n- Raw: !DDMM.MMN/DDDMM.MMW>comment");
        addPacket(new Date().toLocaleTimeString(), "Packet 2: Weather Data", "Detailed info for Packet 2: \n- Temperature: 72F\n- Humidity: 60%\n- Wind: 5mph from NW\n- Raw: _DDMM.MMN/DDDMM.MMW_PHG7200/W80/F60/C270");
        addPacket(new Date().toLocaleTimeString(), "Packet 3: Message to CALL", "Detailed info for Packet 3: \n- To: CALL\n- Message: Hello from HT Commander!\n- Raw: CALL>APRS:Hello from HT Commander!");
        addPacket(new Date().toLocaleTimeString(), "Packet 4: Status Report", "Detailed info for Packet 4: \n- Status: On Air\n- Raw: >STATUS:On Air");
        addPacket(new Date().toLocaleTimeString(), "Packet 5: Unknown Type", "Detailed info for Packet 5: \n- Raw Data: 1A2B3C4D5E6F7890");

        // Resizer functionality
        let isResizing = false;
        resizer.addEventListener('mousedown', (e) => {
            isResizing = true;
            document.body.style.cursor = 'ns-resize'; // Change cursor while dragging
        });

        document.addEventListener('mousemove', (e) => {
            if (!isResizing) return;

            const cardBody = packetListContainer.parentElement; // Get the .card-body
            const cardBodyRect = cardBody.getBoundingClientRect();
            const newHeight = e.clientY - cardBodyRect.top; // Mouse Y relative to card-body top

            // Calculate heights ensuring minimums and maximums
            const totalHeight = cardBodyRect.height;
            const resizerHeight = resizer.offsetHeight;
            const minPacketListHeight = 50; // Minimum height for packet list
            const minPacketDetailsHeight = 50; // Minimum height for packet details

            let calculatedListHeight = newHeight - resizerHeight / 2; // Adjust for resizer center

            if (calculatedListHeight < minPacketListHeight) {
                calculatedListHeight = minPacketListHeight;
            }

            const calculatedDetailsHeight = totalHeight - calculatedListHeight - resizerHeight;
            if (calculatedDetailsHeight < minPacketDetailsHeight) {
                calculatedListHeight = totalHeight - minPacketDetailsHeight - resizerHeight;
                if (calculatedListHeight < minPacketListHeight) {
                    calculatedListHeight = minPacketListHeight; // Ensure list doesn't go below min either
                }
            }

            packetListContainer.style.height = `${calculatedListHeight}px`;
            packetDetailsContainer.style.height = `${totalHeight - calculatedListHeight - resizerHeight}px`;
        });

        document.addEventListener('mouseup', () => {
            isResizing = false;
            document.body.style.cursor = 'default'; // Reset cursor
        });


        // Register Service Worker
        if (('serviceWorker' in navigator) && (location.origin != "file://")) {
            window.addEventListener('load', () => {
                navigator.serviceWorker.register('sw.js')
                    .then(registration => {
                        console.log('ServiceWorker registration successful with scope: ', registration.scope);
                    })
                    .catch(error => {
                        console.log('ServiceWorker registration failed: ', error);
                    });
            });
        }

        // Function to update connect button visibility based on screen size and connection status
        function updateConnectButtonVisibility() {
            const isLargeScreen = window.innerWidth >= 992; // Bootstrap's 'lg' breakpoint

            if (!bluetoothDevice || !bluetoothDevice.gatt.connected) {
                if (isLargeScreen) {
                    leftColumnConnectButton.style.display = 'block';
                } else {
                    leftColumnConnectButton.style.display = 'none';
                }
            } else {
                leftColumnConnectButton.style.display = 'none';
            }
        }

        // Radio toggle logic for small screens
        const radioToggleButton = document.getElementById('radio-toggle-button');
        const leftColumn = document.getElementById('leftColumn');

        // Show Connect button when overlay is active and not connected
        function updateConnectButtonVisibilityInOverlay() {
            const isConnected = bluetoothDevice && bluetoothDevice.gatt && bluetoothDevice.gatt.connected;
            if (!isConnected && leftColumn.classList.contains('overlay-visible')) {
                leftColumnConnectButton.style.display = 'block';
            } else if (!isConnected && window.innerWidth >= 992) {
                leftColumnConnectButton.style.display = 'block';
            } else {
                leftColumnConnectButton.style.display = 'none';
            }
        }

        radioToggleButton.addEventListener('click', () => {
            const isRadioVisible = leftColumn.classList.toggle('overlay-visible');
            radioToggleButton.style['background-color'] = isRadioVisible ? 'gold' : null;
            updateConnectButtonVisibilityInOverlay();
        });

        window.addEventListener('resize', () => {
            manageRadioPanel();
            updateConnectButtonVisibilityInOverlay();
        });
        document.addEventListener('DOMContentLoaded', updateConnectButtonVisibilityInOverlay);

        // Automatically remove overlay-visible class on large screens
        function manageRadioPanel() {
            if (window.innerWidth >= 992) { leftColumn.classList.remove('overlay-visible'); }
            const isRadioVisible = leftColumn.classList.contains('overlay-visible');
            radioToggleButton.style['background-color'] = isRadioVisible ? 'gold' : null;
        }

        window.addEventListener('resize', manageRadioPanel);
        document.addEventListener('DOMContentLoaded', manageRadioPanel);

        // Initial state when the page loads
        document.addEventListener('DOMContentLoaded', () => {
            updateConnectButtonVisibility(); // Set initial visibility
            menuSendCommand.classList.add('disabled');
            modalSendCommandButton.disabled = true;
            sendAprsButton.disabled = true;
        });

        if (websocketMode) { radioStatusDiv.textContent = 'Websocket...'; setupWebSocket(); }
