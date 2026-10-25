package cl.duoc.dsy1107.rabbit_admin_service.security;

import cl.duoc.dsy1107.rabbit_admin_service.RabbitAdminServiceApplication;
import cl.duoc.dsy1107.rabbit_admin_service.service.RabbitAdminService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import java.util.List;
import java.util.Map;
import static org.mockito.Mockito.*;
import static org.springframework.security.test.web.servlet.request.SecurityMockMvcRequestPostProcessors.jwt;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(classes=RabbitAdminServiceApplication.class)
@AutoConfigureMockMvc
class RabbitAdminJwtEp3Test {
    @Autowired MockMvc mvc;
    @MockitoBean RabbitAdminService service;

    @Test void anonymousCannotListQueues() throws Exception {
        mvc.perform(get("/api/admin/queues")).andExpect(status().isUnauthorized());
        verifyNoInteractions(service);
    }
    @Test void loggedInWithoutAdminRoleIsForbidden() throws Exception {
        mvc.perform(get("/api/admin/queues").with(jwt().authorities(new SimpleGrantedAuthority("SCOPE_ot.read"))))
                .andExpect(status().isForbidden());
        verifyNoInteractions(service);
    }
    @Test void adminCanListQueues() throws Exception {
        when(service.listQueues()).thenReturn(List.of(Map.of("name", "demo")));
        mvc.perform(get("/api/admin/queues").with(jwt().authorities(new SimpleGrantedAuthority("ROLE_TALLER_ADMIN"))))
                .andExpect(status().isOk()).andExpect(jsonPath("$[0].name").value("demo"));
        verify(service).listQueues();
    }
    @Test void nonAdminCannotPublish() throws Exception {
        mvc.perform(post("/api/admin/publish")
                .with(jwt().authorities(new SimpleGrantedAuthority("SCOPE_ot.write")))
                .contentType("application/json")
                .content("{\"exchange\":\"demo\",\"routingKey\":\"test\",\"payload\":\"{}\"}"))
                .andExpect(status().isForbidden());
        verifyNoInteractions(service);
    }
    @Test void nonAdminCannotDelete() throws Exception {
        mvc.perform(delete("/api/admin/queues/demo")
                .with(jwt().authorities(new SimpleGrantedAuthority("SCOPE_ot.write"))))
                .andExpect(status().isForbidden());
        verifyNoInteractions(service);
    }
    @Test void unrelatedEndpointRemainsDeniedToAdmin() throws Exception {
        mvc.perform(get("/unrelated").with(jwt().authorities(new SimpleGrantedAuthority("ROLE_TALLER_ADMIN"))))
                .andExpect(status().isForbidden());
    }
}
