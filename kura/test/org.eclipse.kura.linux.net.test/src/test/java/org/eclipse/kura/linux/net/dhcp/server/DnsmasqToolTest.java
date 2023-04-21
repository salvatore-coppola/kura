package org.eclipse.kura.linux.net.dhcp.server;

import static org.junit.Assert.assertEquals;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Map;

import org.eclipse.kura.KuraProcessExecutionErrorException;
import org.eclipse.kura.core.linux.executor.LinuxExitStatus;
import org.eclipse.kura.core.testutil.TestUtil;
import org.eclipse.kura.executor.Command;
import org.eclipse.kura.executor.CommandExecutorService;
import org.eclipse.kura.executor.CommandStatus;
import org.eclipse.kura.linux.net.dhcp.DhcpServerTool;
import org.junit.Before;
import org.junit.Test;

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
 * Eurotech
 ******************************************************************************/

public class DnsmasqToolTest {

    private DnsmasqTool dnsmasqTool;
    private boolean isRunning;
    private CommandExecutorService commandExecutorServiceMock;

    private String tempDir = System.getProperty("java.io.tmpdir");

    @Before
    public void cleanTempFiles() throws IOException {

        Files.find(Paths.get(tempDir), 1, (path, attr) -> path.getName(-1).startsWith("kura-test-"))
                .forEach(tempfile -> {
                    try {
                        Files.deleteIfExists(tempfile);
                    } catch (IOException e) {
                        e.printStackTrace();
                    }
                });

    }

    @Test
    public void shouldCheckDnsmasqToolIsRunning() throws Exception {
        givenDnsmasqTool();
        givenRunningServiceOnInterfaces("iface");

        whenStatusIsCheckedForInterface("iface");

        thenStatusIs(true);
    }

    private void givenDnsmasqTool() {

        this.commandExecutorServiceMock = mock(CommandExecutorService.class);

        this.dnsmasqTool = new DnsmasqTool(commandExecutorServiceMock) {

            @Override
            protected String getConfigFilename(String interfaceName) {
                return tempDir + File.separator + "kura-test-" + interfaceName;
            }
        };
    }

    private void givenRunningServiceOnInterfaces(String... interfaces)
            throws IOException, NoSuchFieldException, NoSuchAlgorithmException {

        @SuppressWarnings("unchecked")
        Map<String, byte[]> configsLastHash = (Map<String, byte[]>) TestUtil.getFieldValue(this.dnsmasqTool,
                "configsLastHash");

        CommandStatus successFullStatus = new CommandStatus(new Command(new String[] {}), new LinuxExitStatus(0));

        for (int i = 0; i < interfaces.length; ++i) {

            String interfaceName = interfaces[i];

            Path interfaceFilepath = Paths.get(tempDir, interfaceName);
            Files.createFile(interfaceFilepath);
            Files.write(interfaceFilepath, "content".getBytes(StandardCharsets.UTF_8));

            configsLastHash.put(interfaceName, sha1(interfaceFilepath));
        }

        Command statusCheckCommand = new Command(
                new String[] { "systemctl", "is-active", "--quiet", DhcpServerTool.DNSMASQ.getValue() });

        when(commandExecutorServiceMock.execute(statusCheckCommand)).thenReturn(successFullStatus);

    }

    private void ginvenStoppedService() {
        CommandStatus notRunningProgramStatus = new CommandStatus(new Command(new String[] {}), new LinuxExitStatus(3));
    }

    private void whenStatusIsCheckedForInterface(String interfaceName) throws KuraProcessExecutionErrorException {
        this.isRunning = this.dnsmasqTool.isRunning(interfaceName);

    }

    private void thenStatusIs(boolean status) {
        assertEquals(this.isRunning, status);

    }

    private byte[] sha1(Path filepath) throws NoSuchAlgorithmException, IOException {

        byte[] fileContent = Files.readAllBytes(filepath);

        MessageDigest digest = MessageDigest.getInstance("SHA-1");
        digest.reset();

        return digest.digest(fileContent);
    }

}
