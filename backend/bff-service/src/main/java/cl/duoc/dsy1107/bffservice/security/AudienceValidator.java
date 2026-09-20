package cl.duoc.dsy1107.bffservice.security;
import org.springframework.security.oauth2.core.*; import org.springframework.security.oauth2.jwt.Jwt;
public class AudienceValidator implements OAuth2TokenValidator<Jwt> { private final String audience; public AudienceValidator(String audience){this.audience=audience;} public OAuth2TokenValidatorResult validate(Jwt jwt){ return jwt.getAudience().contains(audience) ? OAuth2TokenValidatorResult.success() : OAuth2TokenValidatorResult.failure(new OAuth2Error("invalid_token","El audience del JWT no corresponde a esta API",null)); } }
