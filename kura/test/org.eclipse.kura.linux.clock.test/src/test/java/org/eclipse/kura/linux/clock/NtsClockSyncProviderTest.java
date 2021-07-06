package org.eclipse.kura.linux.clock;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assume.assumeTrue;
import static org.mockito.Matchers.anyObject;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.Map;
import java.util.concurrent.atomic.AtomicBoolean;

import org.apache.commons.io.IOUtils;
import org.eclipse.kura.KuraException;
import org.eclipse.kura.core.linux.executor.LinuxExitStatus;
import org.eclipse.kura.core.util.IOUtil;
import org.eclipse.kura.executor.Command;
import org.eclipse.kura.executor.CommandExecutorService;
import org.eclipse.kura.executor.CommandStatus;
import org.junit.Test;

public class NtsClockSyncProviderTest {

    @Test
    public void testSynch() throws NoSuchFieldException, IOException, KuraException {

        assumeTrue("Only run this test on Linux", System.getProperty("os.name").matches("[Ll]inux"));

        InputStream journalEntry = new ByteArrayInputStream(
                IOUtil.readResource("journal-entry.json").getBytes(StandardCharsets.UTF_8));
        OutputStream statusOutputStream = new ByteArrayOutputStream();
        IOUtils.copy(journalEntry, statusOutputStream);

        CommandStatus status = new CommandStatus(new Command(new String[] {}), new LinuxExitStatus(0));
        status.setOutputStream(statusOutputStream);

        CommandExecutorService serviceMock = mock(CommandExecutorService.class);
        when(serviceMock.execute(anyObject())).thenReturn(status);

        NtsClockSyncProvider ntsClockSyncProvider = new NtsClockSyncProvider(serviceMock);
        AtomicBoolean invoked = new AtomicBoolean(false);
        ClockSyncListener listener = new ClockSyncListener() {

            @Override
            public void onClockUpdate(long offset) {
                assertEquals(0, offset);

                invoked.set(true);
            }
        };

        Map<String, Object> properties = new HashMap<>();
        properties.put("enabled", true);
        properties.put("clock.provider", "nts");
        properties.put("clock.nts.config.location", "placeholder_path");

        ntsClockSyncProvider.init(properties, listener);

        boolean synched = ntsClockSyncProvider.syncClock();

        assertTrue(synched);
        assertTrue(invoked.get());
    }
}
