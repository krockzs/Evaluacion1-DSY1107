package cl.duoc.dsy1107.rabbit_admin_service.security;

import cl.duoc.dsy1107.rabbit_admin_service.RabbitAdminServiceApplication;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.webmvc.test.autoconfigure.AutoConfigureMockMvc;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.*;

@SpringBootTest(classes=RabbitAdminServiceApplication.class)
@AutoConfigureMockMvc
class RabbitAdminSecurityEp3Test {
    @Autowired MockMvc mvc;
    @Test void anonymousGetBlocked() throws Exception {
        mvc.perform(get("/api/admin/queues")).andExpect(status().is4xxClientError());
    }
    @Test void anonymousPostBlocked() throws Exception {
        mvc.perform(post("/api/admin/queues").contentType("application/json").content("{\"name\":\"test\"}"))
            .andExpect(status().is4xxClientError());
    }
    @Test void anonymousDeleteBlocked() throws Exception {
        mvc.perform(delete("/api/admin/queues/test")).andExpect(status().is4xxClientError());
    }
}
