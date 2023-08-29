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
package org.eclipse.kura.osgi;

import static org.junit.Assert.assertTrue;

import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import org.eclipse.kura.util.osgi.BundleUtil;
import org.junit.Test;
import org.osgi.framework.Bundle;
import org.osgi.framework.BundleContext;
import org.osgi.framework.FrameworkUtil;

public class BundleUtilTest {

    private Map<String, String> serviceProperties = new HashMap<>();
    private Class<?>[] servicesClasses;
    private Set<Bundle> bundles;

    @Test
    public void shouldReturnGPIOBundle() {

        givenServicesPropertiesFilter("service.pid", "org.eclipse.kura.driver.gpio");
        givenServiceClasses(new Class<?>[] { org.eclipse.kura.driver.Driver.class });

        whenBundleListIsRequested();

        thenBundleNameIs("org.eclipse.kura.driver.gpio.provider");
    }

    private void givenServicesPropertiesFilter(String... properties) {
        for (int i = 0; i < properties.length; i = i + 2) {
            this.serviceProperties.put(properties[i], properties[i + 1]);
        }
    }

    private void givenServiceClasses(Class<?>[] classes) {
        this.servicesClasses = classes;

    }

    private void whenBundleListIsRequested() {
        BundleContext bundleContext = FrameworkUtil.getBundle(this.getClass()).getBundleContext();
        this.bundles = BundleUtil.getBundles(bundleContext, this.servicesClasses, this.serviceProperties);
    }

    private void thenBundleNameIs(String symbolicName) {
        List<String> bundleSymbolicNames = this.bundles.stream().map(Bundle::getSymbolicName)
                .collect(Collectors.toList());

        assertTrue("Wrong bundle found",
                bundleSymbolicNames.size() == 1 && bundleSymbolicNames.get(0).equals(symbolicName));
    }
}
