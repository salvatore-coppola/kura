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

import java.util.Map;
import java.util.Optional;

public enum Resource {

    HUMIDITY(Sensor.HUMIDITY),
    PRESSURE(Sensor.PRESSURE),
    TEMPERATURE_FROM_HUMIDITY(Sensor.TEMPERATURE_FROM_HUMIDITY),
    TEMPERATURE_FROM_PRESSURE(Sensor.TEMPERATURE_FROM_PRESSURE),
    ACCELERATION_X(Sensor.ACCELEROMETER),
    ACCELERATION_Y(Sensor.ACCELEROMETER),
    ACCELERATION_Z(Sensor.ACCELEROMETER),
    MAGNETOMETER_X(Sensor.MAGNETOMETER),
    MAGNETOMETER_Y(Sensor.MAGNETOMETER),
    MAGNETOMETER_Z(Sensor.MAGNETOMETER),
    GYROSCOPE_X(Sensor.GYROSCOPE),
    GYROSCOPE_Y(Sensor.GYROSCOPE),
    GYROSCOPE_Z(Sensor.GYROSCOPE);

    private final Optional<Sensor> associatedSensor;

    private Resource() {
        this.associatedSensor = Optional.empty();
    }

    private Resource(Sensor associatedSensor) {
        this.associatedSensor = Optional.of(associatedSensor);
    }

    public static Resource from(Map<String, Object> channelRecordProperties) {
        final String channelType = (String) channelRecordProperties
                .get(SenseHatChannelDescriptor.SENSEHAT_RESOURCE_PROP_NAME);

        return Resource.valueOf(channelType);
    }

    public Optional<Sensor> getAssociatedSensor() {
        return associatedSensor;
    }

    public boolean isSensorResource() {
        return associatedSensor.isPresent();
    }

    public boolean isFramebufferResource() {
        return !(isSensorResource());
    }

    public enum Sensor {
        ACCELEROMETER,
        GYROSCOPE,
        MAGNETOMETER,
        PRESSURE,
        HUMIDITY,
        TEMPERATURE_FROM_HUMIDITY,
        TEMPERATURE_FROM_PRESSURE
    }
}
