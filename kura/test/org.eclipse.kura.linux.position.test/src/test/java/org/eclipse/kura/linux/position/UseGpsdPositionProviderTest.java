/*******************************************************************************
 * Copyright (c) 2011, 2022 Eurotech and/or its affiliates and others
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
package org.eclipse.kura.linux.position;

import static org.junit.Assert.assertNotNull;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.HashMap;
import java.util.Map;

import org.eclipse.kura.core.testutil.TestUtil;
import org.junit.Test;

import de.taimos.gpsd4java.backend.GPSdEndpoint;
import de.taimos.gpsd4java.backend.ResultParser;
import de.taimos.gpsd4java.types.IGPSObject;
import de.taimos.gpsd4java.types.ParseException;
import de.taimos.gpsd4java.types.SKYObject;
import de.taimos.gpsd4java.types.TPVObject;

public class UseGpsdPositionProviderTest {

    private GpsdPositionProvider gpsdPositionProvider;
    private GPSdEndpoint gpsEndpointMock;
    private ResultParser parser = new ResultParser();

    private String BOLTGATE_10_12_JSON_STREAM = "gpsd-raw-json-boltgate-10-12-el27.1.txt";
    private String BOLTGATE_10_12_JSON_STREAM_2 = "gpsd-raw-json-boltgate-10-12-el27.1_2.txt";
    private String DYNAGATE_20_30_JSON_STREAM = "gpsd-raw-json-dynagate-20-30-el30.txt";

    @Test
    public void startGpsdPositionProvider() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());

        thenIsStartedProperly();
    }

    @Test
    public void stopGpsdPositionProvider() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());

        thenIsStoppedProperly();
    }

    @Test
    public void getPositionFromBoltgate1012Stream() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());
        whenNMEAStreamArriveFrom(BOLTGATE_10_12_JSON_STREAM);

        thenIsStartedProperly();
        thenPositionIsNotNull();
    }

    @Test
    public void getPositionFromBoltgate1012Stream2() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());
        whenNMEAStreamArriveFrom(BOLTGATE_10_12_JSON_STREAM_2);

        thenIsStartedProperly();
        thenPositionIsNotNull();
    }

    @Test
    public void getPositionFromDynaGate2030Stream() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());
        whenNMEAStreamArriveFrom(DYNAGATE_20_30_JSON_STREAM);

        thenIsStartedProperly();
        thenPositionIsNotNull();
    }

    @Test
    public void verifyPositionIsLockedFromDynaGate2030Stream() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());
        whenNMEAStreamArriveFrom(DYNAGATE_20_30_JSON_STREAM);

        thenIsStartedProperly();
        thenPositionIsLocked();
    }

    @Test
    public void getNmeaPositionFromDynaGate2030Stream() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());
        whenNMEAStreamArriveFrom(DYNAGATE_20_30_JSON_STREAM);

        thenIsStartedProperly();
        thenNmeaPositionIsNotNull();
    }

    @Test
    public void getNmeaDateFromDynaGate2030Stream() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());
        whenNMEAStreamArriveFrom(DYNAGATE_20_30_JSON_STREAM);

        thenIsStartedProperly();
        thenNmeaDateIsNotAvailable();
    }

    @Test
    public void getNmeaTimeFromDynaGate2030Stream() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());
        whenNMEAStreamArriveFrom(DYNAGATE_20_30_JSON_STREAM);

        thenIsStartedProperly();
        thenNmeaTimeIsNotAvailable();
    }

    @Test
    public void getDateTimeFromDynaGate2030Stream() {
        givenGpsdPositionProvider();

        whenPropertiesAre(defaultProperties());
        whenNMEAStreamArriveFrom(DYNAGATE_20_30_JSON_STREAM);

        thenIsStartedProperly();
        thenDateTimeIsNotNull();
    }

    private void givenGpsdPositionProvider() {
        this.gpsdPositionProvider = new GpsdPositionProvider();
    }

    private void whenPropertiesAre(Map<String, Object> properties) {
        this.gpsdPositionProvider.init(createOptionsFromProperties(properties), null, null);
        this.gpsEndpointMock = mock(GPSdEndpoint.class);
        try {
            TestUtil.setFieldValue(this.gpsdPositionProvider, "gpsEndpoint", this.gpsEndpointMock);
        } catch (NoSuchFieldException e) {
            e.printStackTrace();
        }
    }

    private void whenNMEAStreamArriveFrom(String filename) {
        try {
            Files.readAllLines(Paths.get("src/test/resources", filename)).forEach(jsonString -> {
                try {
                    IGPSObject gpsObject = this.parser.parse(jsonString);
                    if (gpsObject instanceof TPVObject) {
                        this.gpsdPositionProvider.handleTPV((TPVObject) gpsObject);
                    }
                    if (gpsObject instanceof SKYObject) {
                        this.gpsdPositionProvider.handleSKY((SKYObject) gpsObject);
                    }
                } catch (ParseException e) {
                    e.printStackTrace();
                }
            });
        } catch (IOException e) {
            e.printStackTrace();
        }

    }

    private void thenIsStartedProperly() {
        this.gpsdPositionProvider.start();
        verify(this.gpsEndpointMock).start();
    }

    private void thenIsStoppedProperly() {
        this.gpsdPositionProvider.stop();
        verify(this.gpsEndpointMock).stop();
    }

    private void thenPositionIsNotNull() {
        assertNotNull(this.gpsdPositionProvider.getPosition());
    }

    private void thenNmeaDateIsNotAvailable() {
        try {
            this.gpsdPositionProvider.getNmeaDate();
            fail();
        } catch (UnsupportedOperationException e) {
        }
    }

    private void thenNmeaTimeIsNotAvailable() {
        try {
            this.gpsdPositionProvider.getNmeaTime();
            fail();
        } catch (UnsupportedOperationException e) {
        }
    }

    private void thenNmeaPositionIsNotNull() {
        assertNotNull(this.gpsdPositionProvider.getNmeaPosition());
    }

    private void thenDateTimeIsNotNull() {
        assertNotNull(this.gpsdPositionProvider.getDateTime());
    }

    private void thenPositionIsLocked() {
        assertTrue(this.gpsdPositionProvider.isLocked());
    }

    private PositionServiceOptions createOptionsFromProperties(Map<String, Object> properties) {
        return new PositionServiceOptions(properties);
    }

    private Map<String, Object> defaultProperties() {
        Map<String, Object> propertiesMap = new HashMap<String, Object>();
        propertiesMap.put("enabled", true);
        propertiesMap.put("provider", PositionProviderType.GPSD.getValue());
        propertiesMap.put("gpsd.host", "localhost");
        propertiesMap.put("gpsd.port", 2947);
        return propertiesMap;
    }

}
