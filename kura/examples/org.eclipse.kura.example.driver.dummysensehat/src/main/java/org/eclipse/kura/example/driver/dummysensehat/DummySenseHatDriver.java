/*******************************************************************************
 * Copyright (c) 2023 Eurotech and/or its affiliates and others
 * 
 * This program and the accompanying materials are made
 * available under the terms of the Eclipse Public License 2.0
 * which is available at https://www.eclipse.org/legal/epl-2.0/
 * 
 * SPDX-License-Identifier: EPL-2.0
 * 
 * Contributors:
 *  Eurotech
 *******************************************************************************/

package org.eclipse.kura.example.driver.dummysensehat;

import static java.util.Objects.requireNonNull;

import java.io.IOException;
import java.util.Collections;
import java.util.EnumMap;
import java.util.List;
import java.util.Map;
import java.util.Map.Entry;
import java.util.Set;
import java.util.concurrent.CopyOnWriteArraySet;

import org.eclipse.kura.channel.ChannelFlag;
import org.eclipse.kura.channel.ChannelRecord;
import org.eclipse.kura.channel.ChannelStatus;
import org.eclipse.kura.channel.listener.ChannelListener;
import org.eclipse.kura.configuration.ConfigurableComponent;
import org.eclipse.kura.driver.ChannelDescriptor;
import org.eclipse.kura.driver.Driver;
import org.eclipse.kura.driver.PreparedRead;
import org.eclipse.kura.example.driver.dummysensehat.DummySenseHatInterface.SenseHatReadRequest;
import org.eclipse.kura.type.DataType;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

public class DummySenseHatDriver implements Driver, ConfigurableComponent {

    private static final Logger logger = LoggerFactory.getLogger(DummySenseHatDriver.class);

    private static DummySenseHatInterface senseHatInterface;

    private final Map<Resource, Set<ChannelListenerRegistration>> channelListeners = new EnumMap<>(Resource.class);

    public static synchronized void getSensehatInterface(Boolean anomalyMode) {

        logger.info("Opening Sense Hat...");
        try {
            senseHatInterface = new DummySenseHatInterface(anomalyMode);
        } catch (IOException e) {
            logger.error("Failed to load Dummy SenseHat Interface {}", e.getMessage(), e);
        }
        logger.info("Opening Sense Hat...done");

    }

    public static synchronized void ungetSensehatInteface() {
        logger.info("Closing Sense Hat...");
        try {
            senseHatInterface.close();
        } catch (IOException e) {
            logger.error("Failed to unload Dummy SenseHat Interface {}", e.getMessage(), e);
        }
        logger.info("Closing Sense Hat...done");
        senseHatInterface = null;

    }

    public void activate(final Map<String, Object> properties) {
        logger.info("Activating SenseHat Driver...");
        Boolean anomalyMode = (Boolean) properties.get("anomaly_mode");
        getSensehatInterface(anomalyMode);
        logger.info("Activating SenseHat Driver... Done");
    }

    public void updated(final Map<String, Object> properties) {
        Boolean anomalyMode = (Boolean) properties.get("anomaly_mode");
        ungetSensehatInteface();
        getSensehatInterface(anomalyMode);
    }

    public void deactivate() {
        logger.info("Deactivating SenseHat Driver...");
        try {
            ungetSensehatInteface();
        } catch (Exception e) {
            logger.warn("Failed to close Sense Hat", e);
        }
        logger.info("Deactivating SenseHat Driver... Done");
    }

    @Override
    public void connect() throws ConnectionException {
        // no need
    }

    @Override
    public void disconnect() throws ConnectionException {
        // no need
    }

    @Override
    public void read(final List<ChannelRecord> records) throws ConnectionException {
        senseHatInterface.runReadRequest(toReadRequest(records));
    }

    @Override
    public void registerChannelListener(final Map<String, Object> channelConfig, final ChannelListener listener)
            throws ConnectionException {

        final Resource resource = Resource.from(channelConfig);

        final String channelName = getChannelName(channelConfig);
        final DataType dataType = getChannelValueType(channelConfig);

        if (dataType != DataType.LONG) {
            throw new IllegalArgumentException("Value type for joystick event channels must be: " + DataType.LONG);
        }

        final Set<ChannelListenerRegistration> listeners = getListenersForResource(resource);
        listeners.add(new ChannelListenerRegistration(listener, channelName));
    }

    @Override
    public void unregisterChannelListener(final ChannelListener listener) throws ConnectionException {
        for (Entry<Resource, Set<ChannelListenerRegistration>> e : this.channelListeners.entrySet()) {
            e.getValue().removeIf(registration -> listener == registration.listener);
        }
    }

    @Override
    public void write(final List<ChannelRecord> records) throws ConnectionException {
        throw new UnsupportedOperationException("Writing to Dummy SenseHat is not supported");
    }

    @Override
    public PreparedRead prepareRead(List<ChannelRecord> channelRecords) {
        requireNonNull(channelRecords);

        return new SenseHatPreparedRead(toReadRequest(channelRecords));
    }

    private class SenseHatPreparedRead implements PreparedRead {

        private final SenseHatReadRequest readRequest;

        private SenseHatPreparedRead(final SenseHatReadRequest readRequest) {
            this.readRequest = readRequest;
        }

        @Override
        public List<ChannelRecord> execute() throws ConnectionException {

            senseHatInterface.runReadRequest(this.readRequest);
            return Collections.unmodifiableList(this.readRequest.getRecords());
        }

        @Override
        public List<ChannelRecord> getChannelRecords() {
            return Collections.unmodifiableList(this.readRequest.getRecords());
        }

        @Override
        public void close() {
            // nothing to do
        }
    }

    @Override
    public ChannelDescriptor getChannelDescriptor() {
        return SenseHatChannelDescriptor.instance();
    }

    private void updateRequest(final ChannelRecord channelRecord, final SenseHatReadRequest request) {
        try {
            final Resource resource = Resource.from(channelRecord.getChannelConfig());
            if (resource == Resource.ACCELERATION_X) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getAccelerometerX));
            } else if (resource == Resource.ACCELERATION_Y) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getAccelerometerY));
            } else if (resource == Resource.ACCELERATION_Z) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getAccelerometerZ));
            } else if (resource == Resource.GYROSCOPE_X) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getGyroscopeX));
            } else if (resource == Resource.GYROSCOPE_Y) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getGyroscopeY));
            } else if (resource == Resource.GYROSCOPE_Z) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getGyroscopeZ));
            } else if (resource == Resource.MAGNETOMETER_X) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getMagnetometerX));
            } else if (resource == Resource.MAGNETOMETER_Y) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getMagnetometerY));
            } else if (resource == Resource.MAGNETOMETER_Z) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getMagnetometerZ));
            } else if (resource == Resource.HUMIDITY) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getHumidity));
            } else if (resource == Resource.PRESSURE) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getPressure));
            } else if (resource == Resource.TEMPERATURE_FROM_HUMIDITY) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getTemperatureFromHumidity));
            } else if (resource == Resource.TEMPERATURE_FROM_PRESSURE) {
                request.addTask(new SensorReadTask(channelRecord, DummySenseHatInterface::getTemperatureFromPressure));
            } else {
                throw new IllegalArgumentException("Resource is not readable" + resource);
            }
            resource.getAssociatedSensor().ifPresent(request::addInvolvedSensor);
        } catch (Exception e) {
            channelRecord.setChannelStatus(new ChannelStatus(ChannelFlag.FAILURE, e.getMessage(), e));
            channelRecord.setTimestamp(System.currentTimeMillis());
        }
    }

    public SenseHatReadRequest toReadRequest(final List<ChannelRecord> records) {
        final SenseHatReadRequest result = new SenseHatReadRequest(records);

        for (final ChannelRecord channelRecord : records) {
            updateRequest(channelRecord, result);
        }

        return result;
    }

    private Set<ChannelListenerRegistration> getListenersForResource(Resource resource) {
        return this.channelListeners.computeIfAbsent(resource, res -> new CopyOnWriteArraySet<>());
    }

    private String getChannelName(Map<String, Object> properties) {
        return (String) properties.get("+name");
    }

    private DataType getChannelValueType(Map<String, Object> properties) {
        return DataType.valueOf((String) properties.get("+value.type"));
    }

    private static class ChannelListenerRegistration {

        private final ChannelListener listener;
        private final String channelName;

        public ChannelListenerRegistration(final ChannelListener listener, final String channelName) {
            this.listener = listener;
            this.channelName = channelName;
        }

        @Override
        public int hashCode() {
            final int prime = 31;
            int result = 1;
            result = prime * result + (this.channelName == null ? 0 : this.channelName.hashCode());
            result = prime * result + (this.listener == null ? 0 : this.listener.hashCode());
            return result;
        }

        @Override
        public boolean equals(Object obj) {
            if (this == obj) {
                return true;
            }
            if (obj == null) {
                return false;
            }
            if (getClass() != obj.getClass()) {
                return false;
            }
            ChannelListenerRegistration other = (ChannelListenerRegistration) obj;
            if (this.channelName == null) {
                if (other.channelName != null) {
                    return false;
                }
            } else if (!this.channelName.equals(other.channelName)) {
                return false;
            }
            return this.listener != other.listener;
        }
    }

}
