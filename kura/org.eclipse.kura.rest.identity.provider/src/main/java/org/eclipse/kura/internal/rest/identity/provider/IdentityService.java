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
package org.eclipse.kura.internal.rest.identity.provider;

import java.util.ArrayList;
import java.util.Dictionary;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;
import java.util.Set;

import org.eclipse.kura.KuraErrorCode;
import org.eclipse.kura.KuraException;
import org.eclipse.kura.configuration.ComponentConfiguration;
import org.eclipse.kura.configuration.ConfigurationService;
import org.eclipse.kura.crypto.CryptoService;
import org.eclipse.kura.internal.rest.identity.provider.dto.UserDTO;
import org.eclipse.kura.internal.rest.identity.provider.validator.PasswordStrengthValidators;
import org.eclipse.kura.internal.rest.identity.provider.validator.Validator;
import org.eclipse.kura.internal.rest.identity.provider.validator.ValidatorOptions;
import org.eclipse.kura.util.useradmin.UserAdminHelper;
import org.eclipse.kura.util.useradmin.UserAdminHelper.FallibleConsumer;
import org.osgi.service.useradmin.Role;
import org.osgi.service.useradmin.User;
import org.osgi.service.useradmin.UserAdmin;

@SuppressWarnings("restriction")
public class IdentityService {

    private static final String KURA_WEB_CONSOLE_SERVICE_PID = "org.eclipse.kura.web.Console";
    private static final String PERMISSION_ROLE_NAME_PREFIX = "kura.permission.";
    private static final String USER_ROLE_NAME_PREFIX = "kura.user.";

    private static final String PASSWORD_PROPERTY = "kura.password";
    private static final String KURA_NEED_PASSWORD_CHANGE_PROPERTY = "kura.need.password.change";
    private static final String KURA_NEED_PASSWORD_CHANGE = "kura.need.password.change";

    private UserAdminHelper userAdminHelper;
    private ConfigurationService configurationService;
    private CryptoService cryptoService;

    public IdentityService(CryptoService cryptoService, UserAdmin userAdmin,
            ConfigurationService configurationService) {

        this.configurationService = configurationService;
        this.cryptoService = cryptoService;

        this.userAdminHelper = new UserAdminHelper(userAdmin, cryptoService);
    }

    public void createUser(UserDTO user) throws KuraException {
        if (!this.userAdminHelper.getUser(user.getUserName()).isPresent()) {

            final String password = user.getPassword();
            if (password != null) {
                this.validateUserPassword(password);
            }

            this.userAdminHelper.createUser(user.getUserName());
            this.updateUser(user);
        } else {
            throw new KuraException(KuraErrorCode.BAD_REQUEST, "user " + user.getUserName() + " already exists");
        }
    }

    public void deleteUser(String userName) {
        this.userAdminHelper.deleteUser(userName);
    }

    public UserDTO getUser(String userName) throws KuraException {
        Optional<User> user = this.userAdminHelper.getUser(userName);
        if (user.isPresent()) {
            return initUserConfig(user.get());
        } else {
            throw new KuraException(KuraErrorCode.NOT_FOUND, "user " + userName + " not found");
        }
    }

    public Set<String> getDefinedPermissions() {
        return this.userAdminHelper.getDefinedPermissions();
    }

    public Set<UserDTO> getUserConfig() {
        final Map<String, UserDTO> result = new HashMap<>();

        this.userAdminHelper.foreachUser((name, user) -> {

            final UserDTO userData = initUserConfig(user);

            result.put(user.getName(), userData);
        });

        fillPermissions(result);

        return new HashSet<>(result.values());
    }

    private UserDTO initUserConfig(final User user) {

        final boolean isPasswordEnabled = user.getCredentials().get(PASSWORD_PROPERTY) instanceof String;
        final boolean isPasswordChangeRequired = Objects.equals("true",
                user.getProperties().get(KURA_NEED_PASSWORD_CHANGE_PROPERTY));

        return new UserDTO(getBaseName(user), new HashSet<>(), isPasswordEnabled, isPasswordChangeRequired);
    }

    private static boolean isKuraUser(final Role role) {
        return role.getName().startsWith(USER_ROLE_NAME_PREFIX);
    }

    private static boolean isKuraPermission(final Role role) {
        return role.getName().startsWith(PERMISSION_ROLE_NAME_PREFIX);
    }

    private static String getBaseName(final Role role) {
        final String name = role.getName();

        if (isKuraUser(role)) {
            return name.substring(USER_ROLE_NAME_PREFIX.length());
        } else if (isKuraPermission(role)) {
            return name.substring(PERMISSION_ROLE_NAME_PREFIX.length());
        } else {
            throw new IllegalArgumentException("not a Kura role");
        }
    }

    private void fillPermissions(final Map<String, ? extends UserDTO> userData) {
        this.userAdminHelper.foreachPermission((permission, group) ->

        forEach(group.getMembers(), member -> {
            final UserDTO data = userData.get(member.getName());

            if (data != null) {
                data.getPermissions().add(permission);
            }
        }));
    }

    private static <T, E extends Exception> void forEach(final T[] items, final FallibleConsumer<T, E> consumer)
            throws E {
        if (items != null) {
            for (final T item : items) {
                consumer.accept(item);
            }
        }
    }

    public void updateUser(UserDTO userDTO) throws KuraException {

        final Optional<User> user = this.userAdminHelper.getUser(userDTO.getUserName());

        if (user.isPresent()) {
            this.userAdminHelper.foreachPermission((permissionName, permissionGroup) -> {

                if (userDTO.getPermissions() != null && userDTO.getPermissions().contains(permissionName)) {
                    permissionGroup.addMember(user.get());
                } else {
                    permissionGroup.removeMember(user.get());
                }
            });

            final Dictionary<String, Object> credentials = user.get().getCredentials();

            if (userDTO.isPasswordAuthEnabled()) {
                final String password = userDTO.getPassword();

                if (password != null) {
                    this.validateUserPassword(password);
                    try {
                        credentials.put(PASSWORD_PROPERTY, this.cryptoService.sha256Hash(password));
                    } catch (final Exception e) {
                        throw new KuraException(KuraErrorCode.SERVICE_UNAVAILABLE, e);
                    }
                }
            } else {
                credentials.remove(PASSWORD_PROPERTY);
            }

            final Dictionary<String, Object> properties = user.get().getProperties();

            if (userDTO.isPasswordChangeNeeded()) {
                properties.put(KURA_NEED_PASSWORD_CHANGE, "true");
            } else {
                properties.remove(KURA_NEED_PASSWORD_CHANGE);
            }
        } else {
            throw new KuraException(KuraErrorCode.NOT_FOUND, "user " + userDTO.getUserName() + " not found");
        }

    }

    public void validateUserPassword(String password) throws KuraException {

        ComponentConfiguration consoleConfig = this.configurationService
                .getComponentConfiguration(KURA_WEB_CONSOLE_SERVICE_PID);

        ValidatorOptions validatorOptions = new ValidatorOptions(consoleConfig.getConfigurationProperties());

        final List<Validator<String>> validators = PasswordStrengthValidators.fromConfig(validatorOptions);

        final List<String> errors = new ArrayList<>();

        for (final Validator<String> validator : validators) {
            validator.validate(password, errors::add);
        }

        if (!errors.isEmpty()) {
            throw new KuraException(KuraErrorCode.BAD_REQUEST, "password strenght requirements not satisfied", errors);
        }
    }

}
