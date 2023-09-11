/*******************************************************************************
 * Copyright (c) 2018, 2020 Eurotech and/or its affiliates and others
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

import java.io.Closeable;
import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.lang.reflect.Type;
import java.util.ArrayList;
import java.util.EnumSet;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Random;
import java.util.Set;
import java.util.zip.GZIPInputStream;

import org.eclipse.kura.channel.ChannelRecord;
import org.eclipse.kura.example.driver.dummysensehat.Resource.Sensor;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import com.google.gson.Gson;
import com.google.gson.JsonIOException;
import com.google.gson.JsonSyntaxException;
import com.google.gson.reflect.TypeToken;
import com.google.gson.stream.JsonReader;

public class DummySenseHatInterface implements Closeable {

    private static final Logger logger = LoggerFactory.getLogger(DummySenseHatInterface.class);

    // x,y,z
    private float[] accelerometer = new float[3];
    private float[] gyroscope = new float[3];
    private float[] magnetometer = new float[3];

    private float humidity;
    private float temperatureFromHumidity;

    private float pressure;
    private float temperatureFromPressure;

    private InputStream dummyDataGzipIs;

    private JsonReader jsonReader;
    private Gson gson;

    private Type senseHatToken = new TypeToken<Map<String, String>>() {
    }.getType();

    private boolean anomalyMode;
    private int anomalyPercentage;
    private String anomalyValue;

    private Random random;

    public DummySenseHatInterface(boolean anomalyMode, int anomalyPercentage, float anomalyValue) throws IOException {
        this.anomalyMode = anomalyMode;
        this.anomalyPercentage = anomalyPercentage;
        this.anomalyValue = String.valueOf(anomalyValue);

        this.random = new Random();

        this.gson = new Gson();

        initDummyData();
    }

    @Override
    public void close() throws IOException {
        if (this.jsonReader != null) {
            this.jsonReader.close();
        }

        if (this.dummyDataGzipIs != null) {
            this.dummyDataGzipIs.close();
        }
    }

    public void fetch(Set<Sensor> sensors) {

        try {
            if (this.jsonReader.hasNext()) {

                Map<String, String> element = this.gson.fromJson(this.jsonReader, this.senseHatToken);
                extractFields(sensors, element);
            } else {
                logger.info("Data endend, starting from the beginning");
                close();
                initDummyData();
                fetch(sensors);
            }
        } catch (JsonIOException | JsonSyntaxException | NumberFormatException | IOException e) {
            logger.error("Unable to read Dummy SenseHat data {}", e.getMessage(), e);
        }

    }

    private void extractFields(Set<Sensor> sensors, Map<String, String> element) {

        if (this.anomalyMode) {
            int r = this.random.nextInt(100);

            if (r <= this.anomalyPercentage - 1) {
                element = setAnomalyValue();
            }
        }

        if (sensors.contains(Sensor.ACCELEROMETER)) {
            logger.debug("fetching Accelerometer data...");
            this.accelerometer = toFloatArray(element, "ACC_X", "ACC_Y", "ACC_Z");
            logger.debug("fetching Accelerometer data...done");
        }
        if (sensors.contains(Sensor.GYROSCOPE)) {
            logger.debug("fetching Gyroscope data...");
            this.gyroscope = toFloatArray(element, "GYRO_X", "GYRO_Y", "GYRO_Z");
            logger.debug("fetching Gyroscope data...done");
        }
        if (sensors.contains(Sensor.MAGNETOMETER)) {
            logger.debug("fetching Magnetometer data...");
            this.magnetometer = toFloatArray(element, "MAGNET_X", "MAGNET_Y", "MAGNET_Z");
            logger.debug("fetching Magnetometer data...done");
        }
        if (sensors.contains(Sensor.HUMIDITY)) {
            logger.debug("fetching Humidity data...");
            this.humidity = Float.parseFloat(element.get("HUMIDITY"));
            logger.debug("fetching Humidity data...done");
        }
        if (sensors.contains(Sensor.PRESSURE)) {
            logger.debug("fetching Pressure data...");
            this.pressure = Float.parseFloat(element.get("PRESSURE"));
            logger.debug("fetching Pressure data...done");
        }
        if (sensors.contains(Sensor.TEMPERATURE_FROM_HUMIDITY)) {
            logger.debug("fetching Temperature from Humidity...");
            this.temperatureFromHumidity = Float.parseFloat(element.get("TEMP_HUM"));
            logger.debug("fetching Temperature from Humidity...done");
        }
        if (sensors.contains(Sensor.TEMPERATURE_FROM_PRESSURE)) {
            logger.debug("fetching Temperature from Pressure...");
            this.temperatureFromPressure = Float.parseFloat(element.get("TEMP_PRESS"));
            logger.debug("fetching Temperature from Pressure...done");
        }
    }

    private Map<String, String> setAnomalyValue() {
        Map<String, String> element;
        element = new HashMap<>();
        element.put("HUMIDITY", this.anomalyValue);
        element.put("PRESSURE", this.anomalyValue);
        element.put("TEMP_HUM", this.anomalyValue);
        element.put("TEMP_PRESS", this.anomalyValue);
        element.put("ACC_X", this.anomalyValue);
        element.put("ACC_Y", this.anomalyValue);
        element.put("ACC_Z", this.anomalyValue);
        element.put("GYRO_X", this.anomalyValue);
        element.put("GYRO_Y", this.anomalyValue);
        element.put("GYRO_Z", this.anomalyValue);
        element.put("MAGNET_X", this.anomalyValue);
        element.put("MAGNET_Y", this.anomalyValue);
        element.put("MAGNET_Z", this.anomalyValue);
        return element;
    }

    private float[] toFloatArray(Map<String, String> elem, String... fieldName) {
        float[] floatArray = new float[fieldName.length];

        for (int i = 0; i < floatArray.length; ++i) {
            floatArray[i] = Float.parseFloat(elem.get(fieldName[i]));
        }

        return floatArray;
    }

    private void initDummyData() throws IOException {

        InputStream dummyDataIs = this.getClass().getClassLoader().getResourceAsStream("dummy-data.json.gz");

        if (dummyDataIs == null) {
            logger.error("Unable to find dummy-data.json.gz");
            return;
        }

        this.dummyDataGzipIs = new GZIPInputStream(dummyDataIs);

        this.jsonReader = new JsonReader(new InputStreamReader(this.dummyDataGzipIs));
        this.jsonReader.setLenient(true);

        this.jsonReader.beginArray();
    }

    public float getAccelerometerX() {
        return this.accelerometer[0];
    }

    public float getAccelerometerY() {
        return this.accelerometer[1];
    }

    public float getAccelerometerZ() {
        return this.accelerometer[2];
    }

    public float getGyroscopeX() {
        return this.gyroscope[0];
    }

    public float getGyroscopeY() {
        return this.gyroscope[1];
    }

    public float getGyroscopeZ() {
        return this.gyroscope[2];
    }

    public float getMagnetometerX() {
        return this.magnetometer[0];
    }

    public float getMagnetometerY() {
        return this.magnetometer[1];
    }

    public float getMagnetometerZ() {
        return this.magnetometer[2];
    }

    public float getPressure() {
        return pressure;
    }

    public float getHumidity() {
        return humidity;
    }

    public float getTemperatureFromHumidity() {
        return temperatureFromHumidity;
    }

    public float getTemperatureFromPressure() {
        return temperatureFromPressure;
    }

    public synchronized void runReadRequest(SenseHatReadRequest request) {
        this.fetch(request.getInvolvedSensors());
        request.getTasks().forEach(task -> task.exec(this));
    }

    public static class SenseHatReadRequest {

        private final EnumSet<Sensor> involvedSensors;
        private final List<ChannelRecord> records;
        private final List<ReadTask> tasks;

        protected SenseHatReadRequest(List<ChannelRecord> records) {
            this.records = records;
            this.involvedSensors = EnumSet.noneOf(Sensor.class);
            this.tasks = new ArrayList<>(records.size());
        }

        protected void addInvolvedSensor(Sensor sensor) {
            this.involvedSensors.add(sensor);
        }

        protected void addTask(ReadTask task) {
            this.tasks.add(task);
        }

        public Set<Sensor> getInvolvedSensors() {
            return involvedSensors;
        }

        public List<ChannelRecord> getRecords() {
            return records;
        }

        public List<ReadTask> getTasks() {
            return tasks;
        }
    }

}
