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
package org.eclipse.kura.internal.rest.identity.provider.test;

import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.reset;
import static org.mockito.Mockito.when;

import java.util.Arrays;
import java.util.Collection;
import java.util.Collections;
import java.util.Dictionary;
import java.util.HashSet;
import java.util.Hashtable;
import java.util.Optional;
import java.util.Scanner;
import java.util.Set;
import java.util.concurrent.TimeUnit;

import org.eclipse.kura.KuraException;
import org.eclipse.kura.core.testutil.requesthandler.AbstractRequestHandlerTest;
import org.eclipse.kura.core.testutil.requesthandler.MqttTransport;
import org.eclipse.kura.core.testutil.requesthandler.RestTransport;
import org.eclipse.kura.core.testutil.requesthandler.Transport;
import org.eclipse.kura.core.testutil.requesthandler.Transport.MethodSpec;
import org.eclipse.kura.internal.rest.identity.provider.IdentityRestService;
import org.eclipse.kura.internal.rest.identity.provider.IdentityService;
import org.eclipse.kura.internal.rest.identity.provider.dto.UserConfigDTO;
import org.eclipse.kura.internal.rest.identity.provider.dto.UserDTO;
import org.eclipse.kura.util.wire.test.WireTestUtil;
import org.junit.BeforeClass;
import org.junit.Test;
import org.junit.runner.RunWith;
import org.junit.runners.Parameterized;
import org.osgi.framework.FrameworkUtil;
import org.osgi.service.cm.Configuration;
import org.osgi.service.cm.ConfigurationAdmin;

import com.google.gson.Gson;

@RunWith(Parameterized.class)
public class IdentityEndpointsTest extends AbstractRequestHandlerTest {

    private static final String MQTT_APP_ID = "ID-V1";

    private static final String METHOD_SPEC_GET = "GET";
    private static final String METHOD_SPEC_POST = "POST";
    private static final String METHOD_SPEC_DELETE = "DELETE";
    private static final String MQTT_METHOD_SPEC_DEL = "DEL";
    private static final String REST_APP_ID = "identity/v1";

    private static IdentityService identityServiceMock = mock(IdentityService.class);

    private static UserDTO user;

    private Gson gson = new Gson();

    private static final String EXPECTED_GET_USER_CONFIG_RESPONSE = new Scanner(
            IdentityEndpointsTest.class.getResourceAsStream("/getUserConfigResponse.json"), "UTF-8").useDelimiter("\\A")
                    .next().replace(" ", "");

    private static final String EXPECTED_GET_USER_RESPONSE = new Scanner(
            IdentityEndpointsTest.class.getResourceAsStream("/getUserResponse.json"), "UTF-8").useDelimiter("\\A")
                    .next().replace(" ", "");

    private UserConfigDTO userConfigRequest;

    private static Set<UserDTO> userConfigs;

    @Parameterized.Parameters
    public static Collection<Transport> transports() {
        return Arrays.asList(new RestTransport(REST_APP_ID), new MqttTransport(MQTT_APP_ID));
    }

    public IdentityEndpointsTest(Transport transport) {
        super(transport);
    }

    @Test
    public void shouldInvokeCreateUserSuccessfully() throws KuraException {
        givenUser(new UserDTO("testuser", Collections.emptySet(), true, false, "testpassw"));

        givenIdentityService();

        whenRequestIsPerformed(new MethodSpec(METHOD_SPEC_POST), "/users", gson.toJson(user));

        thenRequestSucceeds();
        thenResponseBodyIsEmpty();
    }

    @Test
    public void shouldInvokeDeleteUserSuccessfully() throws KuraException {
        givenUser(new UserDTO("testuser", Collections.emptySet(), true, false, "testpassw"));

        givenIdentityService();

        whenRequestIsPerformed(new MethodSpec(METHOD_SPEC_DELETE, MQTT_METHOD_SPEC_DEL), "/users", gson.toJson(user));

        thenRequestSucceeds();
        thenResponseBodyIsEmpty();
    }

    @Test
    public void shouldReturnUserSuccessfully() throws KuraException {
        givenUser(new UserDTO("testuser3", Collections.emptySet(), true, false));

        givenIdentityService();

        whenRequestIsPerformed(new MethodSpec(METHOD_SPEC_GET, METHOD_SPEC_GET), "/users", gson.toJson(user));

        thenRequestSucceeds();
        thenResponseBodyEqualsJson(EXPECTED_GET_USER_RESPONSE);
    }

    @Test
    public void shouldReturnDefinedPermissions() throws KuraException {
        givenIdentityService();

        whenRequestIsPerformed(new MethodSpec(METHOD_SPEC_GET), "/defined-permissions");

        thenRequestSucceeds();
        thenResponseBodyEqualsJson("{\"permissions\": [\"perm1\",\"perm2\"]}");
    }

    @Test
    public void shouldReturnUserConfig() throws KuraException {
        givenUserConfigs(new UserDTO("testuser2", //
                new HashSet<String>(Arrays.asList("perm1", "perm2")), //
                false, //
                true, //
                "testpassw2"));

        givenIdentityService();

        whenRequestIsPerformed(new MethodSpec(METHOD_SPEC_GET), "/users/configs");

        thenRequestSucceeds();
        thenResponseBodyEqualsJson(EXPECTED_GET_USER_CONFIG_RESPONSE);
    }

    @Test
    public void shouldInvokeSetUserConfigSuccessfully() throws KuraException {
        givenUserConfigRequest(new UserDTO("testuser", Collections.emptySet(), true, false, "testpassw"), new UserDTO(
                "testuser2", new HashSet<String>(Arrays.asList("perm1", "perm2")), false, true, "testpassw2"));

        givenIdentityService();

        whenRequestIsPerformed(new MethodSpec(METHOD_SPEC_POST), "/users/configs", gson.toJson(this.userConfigRequest));

        thenRequestSucceeds();
    }

    private void givenUser(UserDTO userParam) {
        user = userParam;
    }

    private void givenUserConfigs(UserDTO... userConfigurations) {
        userConfigs = new HashSet<>(Arrays.asList(userConfigurations));
    }

    private void givenUserConfigRequest(UserDTO... userDTO) {
        this.userConfigRequest = new UserConfigDTO();
        this.userConfigRequest.setUserConfig(new HashSet<>(Arrays.asList(userDTO)));

    }

    private static void givenIdentityService() throws KuraException {
        reset(identityServiceMock);

        when(identityServiceMock.getDefinedPermissions())
                .thenReturn(new HashSet<String>(Arrays.asList("perm1", "perm2")));

        when(identityServiceMock.getUserConfig()).thenReturn(userConfigs);

        if (user != null) {
            when(identityServiceMock.getUser("testuser3"))
                    .thenReturn(new UserDTO("testuser3", Collections.emptySet(), true, false));

            when(identityServiceMock.getUser("testuser"))
                    .thenReturn(new UserDTO("testuser", Collections.emptySet(), true, false));
        }
    }

    @BeforeClass
    public static void setUp() throws Exception {
        createIdentityServiceMock();
        registerIdentityServiceMock();
    }

    private static void createIdentityServiceMock() throws KuraException {
        givenIdentityService();

        final Dictionary<String, Object> configurationServiceProperties = new Hashtable<>();
        configurationServiceProperties.put("service.ranking", Integer.MIN_VALUE);
        configurationServiceProperties.put("kura.service.pid", "identityServiceMock");
        FrameworkUtil.getBundle(IdentityEndpointsTest.class).getBundleContext().registerService(IdentityService.class,
                identityServiceMock, configurationServiceProperties);
    }

    private static void registerIdentityServiceMock() throws Exception {
        final Dictionary<String, Object> properties = new Hashtable<>();
        properties.put("IdentityService.target", "(kura.service.pid=identityServiceMock)");

        final ConfigurationAdmin configurationAdmin = WireTestUtil
                .trackService(ConfigurationAdmin.class, Optional.empty()).get(30, TimeUnit.SECONDS);
        final Configuration config = configurationAdmin.getConfiguration(IdentityRestService.class.getName(), "?");
        config.update(properties);
    }

}
