/** @typedef {'es'|'en'|'pt'} Locale */

window.KLOOVI_LOCALES = {
  es: {
    htmlLang: "es",
    metaTitleHome: "Kloovi — Conecta. Juega. Comparte.",
    metaDescHome:
      "Kloovi ayuda a organizar partidos y administrar cobros del grupo. No es una app financiera: no recibe ni procesa pagos.",
    metaTitlePrivacy: "Política de Privacidad — Kloovi",
    metaDescPrivacy:
      "Política de privacidad de Kloovi: qué datos tratamos y aclaración de que no procesamos pagos.",
    metaTitleTerms: "Términos de Servicio — Kloovi",
    metaDescTerms:
      "Términos de uso de Kloovi. No somos una app financiera: no recibimos ni procesamos pagos.",
    navHow: "Cómo funciona",
    navPrivacy: "Privacidad",
    navTerms: "Términos",
    navHome: "Inicio",
    navContact: "Contacto",
    heroLead:
      "Conecta. Juega. Comparte. Organiza el partido y lleva los cobros del grupo sin drama.",
    ctaHow: "Ver cómo funciona",
    ctaPrivacy: "Política de privacidad",
    heroNote:
      "Disponible pronto en Google Play. Kloovi no recibe dinero ni procesa pagos: solo te ayuda a administrar comprobantes y saldos del grupo.",
    howTitle: "Una app para el grupo, no un banco",
    howSub:
      "Pensada para organizadores y jugadores de pádel u otros deportes: convocatorias, confirmaciones y seguimiento de quién ya aportó.",
    point1Title: "Organiza",
    point1Body:
      "Arma el encuentro, invita al roster y mira quién confirma, quién falta o quién queda como suplente.",
    point2Title: "Administra cobros",
    point2Body:
      "Registra quién pagó, guarda comprobantes (fotos) y lleva saldos del grupo dentro de la app.",
    point3Title: "Sin pasarela de pago",
    point3Body:
      "Kloovi no cobra a jugadores ni recibe transferencias. El dinero se mueve fuera de la app, entre ustedes.",
    calloutTitle: "Importante para Play Store y usuarios",
    calloutBody:
      "Kloovi <strong>no es una aplicación financiera</strong>. No es billetera, banco, procesador de pagos ni intermediario de dinero. Solo almacena información administrativa y comprobantes que el organizador o el jugador cargan para llevar el control del grupo.",
    contactTitle: "Contacto",
    contactSub: "¿Dudas de privacidad, cuenta o publicación?",
    footerCopy: "© {year} Kloovi · kloovi.app",
    privacyH1: "Política de Privacidad",
    privacyMeta: "Última actualización: 13 de julio de 2026 · Responsable: Kloovi (kloovi.app)",
    termsH1: "Términos de Servicio",
    termsMeta: "Última actualización: 13 de julio de 2026 · Kloovi (kloovi.app)",
    backHome: "← Kloovi",
    privacyHtml: `
      <div class="notice">
        <strong>Kloovi no es una app financiera</strong>
        Kloovi no recibe, custodia, transfiere ni procesa dinero. No somos un banco, billetera electrónica, procesador de pagos (PSP) ni intermediario de cobros. La app solo ayuda a organizar partidos y a <em>administrar</em> información de cobros del grupo (por ejemplo, quién aportó y comprobantes fotográficos). Cualquier pago real ocurre fuera de Kloovi, entre organizador y jugadores (transferencia, efectivo u otro medio elegido por ustedes).
      </div>
      <p>Esta Política explica qué datos personales tratamos cuando usas la aplicación móvil Kloovi y el sitio <a href="https://kloovi.app">kloovi.app</a>, con qué finalidades, con quién los compartimos y qué derechos tienes. Contacto de privacidad: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>1. Quiénes somos</h2>
      <p>Kloovi es una aplicación de organización deportiva y administración de gastos/cobros de grupos (por ejemplo, canchas, pelotas u otros aportes del partido). El responsable del tratamiento es el operador de Kloovi, contactable en el correo indicado arriba.</p>
      <h2>2. Qué datos tratamos</h2>
      <p>Según cómo uses la app, podemos tratar:</p>
      <ul>
        <li><strong>Cuenta e identidad:</strong> nombre, correo electrónico, foto de perfil (si inicia sesión con Google o los cargas tú), identificador de usuario.</li>
        <li><strong>Datos de uso del grupo:</strong> encuentros, convocatorias, confirmaciones, roster, saldos y conceptos administrativos.</li>
        <li><strong>Comprobantes:</strong> imágenes o archivos que un usuario sube como evidencia de un pago hecho <em>fuera</em> de la app. Kloovi no ejecuta el pago.</li>
        <li><strong>Dispositivo y notificaciones:</strong> token push (FCM), idioma/preferencias, diagnósticos de estabilidad si están habilitados.</li>
        <li><strong>Soporte:</strong> contenido que nos envíes por correo.</li>
      </ul>
      <p>No solicitamos datos de tarjetas bancarias, claves de banco, CVV ni credenciales de pasarelas, porque Kloovi <strong>no procesa pagos</strong>.</p>
      <h2>3. Finalidades</h2>
      <ul>
        <li>Crear y autenticar tu cuenta (incluido Acceder con Google).</li>
        <li>Organizar encuentros, invitaciones, confirmaciones y comunicación del grupo.</li>
        <li>Permitir al organizador administrar cobros (registros, saldos y revisión de comprobantes).</li>
        <li>Enviar notificaciones relacionadas con la app, si otorgas permiso.</li>
        <li>Seguridad, prevención de abuso y estabilidad del servicio.</li>
        <li>Cumplir obligaciones legales aplicables.</li>
      </ul>
      <h2>4. Base del tratamiento</h2>
      <p>Tratamos datos porque son necesarios para prestar el servicio, por tu consentimiento cuando aplica (notificaciones, cámara/galería) y por interés legítimo de seguridad y mejora, sin menoscabar tus derechos.</p>
      <h2>5. Proveedores</h2>
      <ul>
        <li><strong>Supabase</strong> — autenticación, base de datos y almacenamiento.</li>
        <li><strong>Google</strong> — Acceder con Google, FCM y, si corresponde, Analytics/Crashlytics.</li>
        <li><strong>Vercel</strong> — alojamiento de este sitio.</li>
      </ul>
      <p>No vendemos tus datos personales.</p>
      <h2>6. Comprobantes y “no somos app financiera”</h2>
      <p>Un comprobante es evidencia administrativa de un pago externo. Kloovi: no inicia transferencias; no recibe fondos; no remesa dinero; no actúa como pasarela ni billetera; no garantiza el cobro entre particulares.</p>
      <h2>7. Conservación</h2>
      <p>Conservamos datos mientras mantengas la cuenta y sea necesario para el servicio. Puedes solicitar eliminación en <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>8. Seguridad</h2>
      <p>Aplicamos medidas razonables (acceso controlado, HTTPS). Ningún sistema es 100% infalible.</p>
      <h2>9. Tus derechos</h2>
      <p>Según la ley aplicable (incluida normativa chilena cuando corresponda), puedes solicitar acceso, rectificación, oposición, limitación o eliminación, y retirar consentimientos. Escríbenos a <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>10. Menores</h2>
      <p>Kloovi no está dirigida a menores de 13 años (o la edad mínima de tu jurisdicción).</p>
      <h2>11. Transferencias internacionales</h2>
      <p>Proveedores pueden procesar datos fuera de tu país, con las salvaguardas que ofrezcan.</p>
      <h2>12. Cambios</h2>
      <p>Publicaremos la versión vigente en <a href="https://kloovi.app/privacy">kloovi.app/privacy</a>.</p>
      <h2>13. Contacto</h2>
      <p>Privacidad: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a><br />Sitio: <a href="https://kloovi.app">https://kloovi.app</a></p>
    `,
    termsHtml: `
      <div class="notice">
        <strong>Declaración clave (Google Play / usuarios)</strong>
        Kloovi <strong>no es una aplicación financiera</strong>. No ofrece servicios bancarios, de crédito, remesas, inversión, criptomonedas ni procesamiento de pagos. <strong>Kloovi no recibe dinero</strong>. Solo permite registrar y administrar cobros del grupo y recibir <strong>comprobantes</strong> (p. ej. fotos) para gestión interna. Los pagos reales se realizan fuera de la app.
      </div>
      <p>Al usar Kloovi o <a href="https://kloovi.app">kloovi.app</a>, aceptas estos Términos. Contacto: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>1. Descripción del servicio</h2>
      <ul>
        <li>Organizar encuentros e invitaciones/confirmaciones.</li>
        <li>Mantener un roster de jugadores.</li>
        <li>Registrar aportes, saldos y conceptos del grupo.</li>
        <li>Adjuntar y revisar comprobantes de pagos externos.</li>
      </ul>
      <h2>2. Lo que Kloovi no es y no hace</h2>
      <ul>
        <li>No somos entidad financiera ni emisora de medios de pago.</li>
        <li>No recibimos, custodiamos ni transferimos fondos.</li>
        <li>No iniciamos débitos ni cargos a tarjetas.</li>
        <li>No somos pasarela, agregador, billetera ni escrow.</li>
        <li>No garantizamos pagos entre particulares ni mediamos legalmente el cobro.</li>
      </ul>
      <p>Cualquier pago ocurre fuera de Kloovi, entre las personas del grupo.</p>
      <h2>3. Comprobantes</h2>
      <p>Son archivos (p. ej. fotos) como evidencia de un pago externo. El organizador decide cómo validarlos. Kloovi no verifica autenticidad bancaria automática ni responde por comprobantes falsos.</p>
      <h2>4. Cuentas</h2>
      <p>Información veraz; edad mínima legal (al menos 13 años). Puede haber roles jugador/organizador y, en el futuro, planes de suscripción del organizador (software, no servicio financiero).</p>
      <h2>5. Conducta</h2>
      <p>No uses Kloovi para fraude, lavado de dinero, acoso u otras ilegalidades; ni presentes la app como banco o procesador de pagos.</p>
      <h2>6. Contenido del usuario</h2>
      <p>Conservas derechos sobre lo que subes; nos das licencia limitada para operar el servicio. Ver <a href="/privacy">Privacidad</a>.</p>
      <h2>7. Notificaciones y permisos</h2>
      <p>Push y cámara/galería solo con tu permiso, para funciones de la app.</p>
      <h2>8. Suscripciones (si aplican)</h2>
      <p>Un cobro por software al organizador no es un pago “en nombre” de jugadores ni un servicio financiero.</p>
      <h2>9. Disponibilidad</h2>
      <p>Servicio “tal cual” y según disponibilidad; pueden existir interrupciones.</p>
      <h2>10. Limitación de responsabilidad</h2>
      <p>Kloovi no responde por disputas de pago entre usuarios ni por canchas/reservas externas. Nada limita derechos inalienables del consumidor cuando la ley lo prohíbe.</p>
      <h2>11. Propiedad intelectual</h2>
      <p>Marca y software Kloovi pertenecen a sus titulares.</p>
      <h2>12. Terminación</h2>
      <p>Puedes dejar de usar la app; podemos suspender cuentas que vulneren estos Términos.</p>
      <h2>13. Privacidad</h2>
      <p>Se rige por la <a href="/privacy">Política de Privacidad</a>.</p>
      <h2>14. Ley aplicable</h2>
      <p>Leyes de Chile, sin perjuicio de normas imperativas de tu residencia.</p>
      <h2>15. Contacto</h2>
      <p><a href="mailto:hello@kloovi.app">hello@kloovi.app</a> · <a href="https://kloovi.app">kloovi.app</a></p>
    `,
  },

  en: {
    htmlLang: "en",
    metaTitleHome: "Kloovi — Connect. Play. Share.",
    metaDescHome:
      "Kloovi helps organize matches and track group collections. Not a financial app: we do not receive or process payments.",
    metaTitlePrivacy: "Privacy Policy — Kloovi",
    metaDescPrivacy:
      "Kloovi privacy policy: what data we process and why we are not a payment processor.",
    metaTitleTerms: "Terms of Service — Kloovi",
    metaDescTerms:
      "Kloovi terms of use. Not a financial app: we do not receive or process payments.",
    navHow: "How it works",
    navPrivacy: "Privacy",
    navTerms: "Terms",
    navHome: "Home",
    navContact: "Contact",
    heroLead:
      "Connect. Play. Share. Organize the match and keep group collections without the chaos.",
    ctaHow: "See how it works",
    ctaPrivacy: "Privacy policy",
    heroNote:
      "Coming soon on Google Play. Kloovi does not receive money or process payments—it only helps you manage receipts and group balances.",
    howTitle: "An app for the group, not a bank",
    howSub:
      "Built for organizers and players of padel and other sports: summons, confirmations, and tracking who already chipped in.",
    point1Title: "Organize",
    point1Body:
      "Set up the match, invite your roster, and see who confirmed, who’s missing, or who’s on the waitlist.",
    point2Title: "Track collections",
    point2Body:
      "Record who paid, store receipt photos, and follow group balances inside the app.",
    point3Title: "No payment gateway",
    point3Body:
      "Kloovi does not charge players or receive transfers. Money moves outside the app, between you.",
    calloutTitle: "Important for Play Store and users",
    calloutBody:
      "Kloovi <strong>is not a financial application</strong>. It is not a wallet, bank, payment processor, or money intermediary. It only stores administrative information and receipts that organizers or players upload to keep the group organized.",
    contactTitle: "Contact",
    contactSub: "Questions about privacy, your account, or publishing?",
    footerCopy: "© {year} Kloovi · kloovi.app",
    privacyH1: "Privacy Policy",
    privacyMeta: "Last updated: July 13, 2026 · Controller: Kloovi (kloovi.app)",
    termsH1: "Terms of Service",
    termsMeta: "Last updated: July 13, 2026 · Kloovi (kloovi.app)",
    backHome: "← Kloovi",
    privacyHtml: `
      <div class="notice">
        <strong>Kloovi is not a financial app</strong>
        Kloovi does not receive, hold, transfer, or process money. We are not a bank, e-wallet, payment service provider (PSP), or collection intermediary. The app only helps organize matches and <em>administer</em> group collection information (who contributed, receipt photos, etc.). Any real payment happens outside Kloovi, between organizer and players.
      </div>
      <p>This Policy explains what personal data we process when you use the Kloovi mobile app and <a href="https://kloovi.app">kloovi.app</a>. Privacy contact: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>1. Who we are</h2>
      <p>Kloovi is a sports organization and group expense/collection administration app (e.g. courts, balls, or other match contributions). The controller is the operator of Kloovi, reachable at the email above.</p>
      <h2>2. Data we process</h2>
      <ul>
        <li><strong>Account &amp; identity:</strong> name, email, profile photo (e.g. via Google Sign-In), user ID.</li>
        <li><strong>Group usage data:</strong> matches, summons, confirmations, roster, balances, and administrative labels.</li>
        <li><strong>Receipts:</strong> images/files uploaded as evidence of a payment made <em>outside</em> the app. Kloovi does not execute the payment.</li>
        <li><strong>Device &amp; notifications:</strong> FCM push token, language/preferences, stability diagnostics if enabled.</li>
        <li><strong>Support:</strong> content you email us.</li>
      </ul>
      <p>We do not ask for bank card numbers, bank passwords, CVV, or payment-gateway credentials because Kloovi <strong>does not process payments</strong>.</p>
      <h2>3. Purposes</h2>
      <ul>
        <li>Create and authenticate accounts (including Google Sign-In).</li>
        <li>Organize matches, invitations, confirmations, and group communication.</li>
        <li>Let organizers administer collections (records, balances, receipt review).</li>
        <li>Send app-related notifications if you allow them.</li>
        <li>Security, abuse prevention, and service stability.</li>
        <li>Comply with applicable legal obligations.</li>
      </ul>
      <h2>4. Legal bases</h2>
      <p>We process data to provide the service, based on consent where required (notifications, camera/gallery), and for legitimate interests in security and improvement, without overriding your rights.</p>
      <h2>5. Providers</h2>
      <ul>
        <li><strong>Supabase</strong> — auth, database, and storage.</li>
        <li><strong>Google</strong> — Sign in with Google, FCM, and Analytics/Crashlytics if enabled.</li>
        <li><strong>Vercel</strong> — website hosting.</li>
      </ul>
      <p>We do not sell your personal data.</p>
      <h2>6. Receipts &amp; “not a financial app”</h2>
      <p>A receipt is administrative evidence of an external payment. Kloovi does not initiate transfers, receive funds, remit money, act as a gateway/wallet, or guarantee collection between private parties.</p>
      <h2>7. Retention</h2>
      <p>We keep data while your account exists and as needed for the service. You may request deletion at <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>8. Security</h2>
      <p>We apply reasonable measures (access control, HTTPS). No system is 100% secure.</p>
      <h2>9. Your rights</h2>
      <p>Depending on applicable law (including Chilean rules when relevant), you may request access, rectification, objection, restriction, or deletion, and withdraw consents. Email <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>10. Children</h2>
      <p>Kloovi is not directed to children under 13 (or the minimum age in your jurisdiction).</p>
      <h2>11. International transfers</h2>
      <p>Providers may process data outside your country under their safeguards.</p>
      <h2>12. Changes</h2>
      <p>The current version will be published at <a href="https://kloovi.app/privacy">kloovi.app/privacy</a>.</p>
      <h2>13. Contact</h2>
      <p>Privacy: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a><br />Site: <a href="https://kloovi.app">https://kloovi.app</a></p>
    `,
    termsHtml: `
      <div class="notice">
        <strong>Key statement (Google Play / users)</strong>
        Kloovi <strong>is not a financial application</strong>. It does not provide banking, credit, remittance, investment, crypto, or payment-processing services. <strong>Kloovi does not receive money</strong>. It only lets groups record and administer collections and upload <strong>receipts</strong> (e.g. photos) for internal tracking. Real payments happen outside the app.
      </div>
      <p>By using Kloovi or <a href="https://kloovi.app">kloovi.app</a>, you agree to these Terms. Contact: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>1. Service description</h2>
      <ul>
        <li>Organize matches and invitations/confirmations.</li>
        <li>Maintain a player roster.</li>
        <li>Track contributions, balances, and group labels.</li>
        <li>Attach and review receipts for external payments.</li>
      </ul>
      <h2>2. What Kloovi is not</h2>
      <ul>
        <li>Not a financial institution or payment-instrument issuer.</li>
        <li>Does not receive, hold, or transfer funds.</li>
        <li>Does not debit cards or initiate bank charges.</li>
        <li>Not a payment gateway, aggregator, wallet, or escrow.</li>
        <li>Does not guarantee private-party payments or legally mediate collection.</li>
      </ul>
      <p>Any payment occurs outside Kloovi, among group members.</p>
      <h2>3. Receipts</h2>
      <p>Files (often photos) evidencing an external payment. The organizer decides how to validate them. Kloovi does not auto-verify bank authenticity and is not liable for forged receipts.</p>
      <h2>4. Accounts</h2>
      <p>Provide accurate information; meet the legal minimum age (at least 13). Roles may include player/organizer; organizer software subscriptions (if any) are not financial services.</p>
      <h2>5. Acceptable use</h2>
      <p>Do not use Kloovi for fraud, money laundering, harassment, or other illegal activity; do not present the app as a bank or payment processor.</p>
      <h2>6. User content</h2>
      <p>You keep rights to what you upload; you grant a limited license to operate the service. See <a href="/privacy">Privacy</a>.</p>
      <h2>7. Notifications &amp; permissions</h2>
      <p>Push and camera/gallery only with your permission, for app features.</p>
      <h2>8. Subscriptions (if any)</h2>
      <p>Charging organizers for software is not collecting player match fees through Kloovi and is not a financial product.</p>
      <h2>9. Availability</h2>
      <p>Service is provided “as is” and as available; interruptions may occur.</p>
      <h2>10. Limitation of liability</h2>
      <p>Kloovi is not liable for payment disputes among users or for external court bookings. Nothing limits non-waivable consumer rights where prohibited by law.</p>
      <h2>11. Intellectual property</h2>
      <p>Kloovi marks and software belong to their owners.</p>
      <h2>12. Termination</h2>
      <p>You may stop using the app; we may suspend accounts that violate these Terms.</p>
      <h2>13. Privacy</h2>
      <p>Governed by the <a href="/privacy">Privacy Policy</a>.</p>
      <h2>14. Governing law</h2>
      <p>Laws of Chile, without prejudice to mandatory rules of your residence.</p>
      <h2>15. Contact</h2>
      <p><a href="mailto:hello@kloovi.app">hello@kloovi.app</a> · <a href="https://kloovi.app">kloovi.app</a></p>
    `,
  },

  pt: {
    htmlLang: "pt",
    metaTitleHome: "Kloovi — Conecta. Joga. Comparte.",
    metaDescHome:
      "Kloovi ajuda a organizar partidas e administrar cobranças do grupo. Não é um app financeiro: não recebe nem processa pagamentos.",
    metaTitlePrivacy: "Política de Privacidade — Kloovi",
    metaDescPrivacy:
      "Política de privacidade da Kloovi: quais dados tratamos e por que não processamos pagamentos.",
    metaTitleTerms: "Termos de Serviço — Kloovi",
    metaDescTerms:
      "Termos de uso da Kloovi. Não somos um app financeiro: não recebemos nem processamos pagamentos.",
    navHow: "Como funciona",
    navPrivacy: "Privacidade",
    navTerms: "Termos",
    navHome: "Início",
    navContact: "Contato",
    heroLead:
      "Conecta. Joga. Comparte. Organize a partida e acompanhe as cobranças do grupo sem estresse.",
    ctaHow: "Ver como funciona",
    ctaPrivacy: "Política de privacidade",
    heroNote:
      "Em breve no Google Play. A Kloovi não recebe dinheiro nem processa pagamentos: só ajuda a administrar comprovantes e saldos do grupo.",
    howTitle: "Um app para o grupo, não um banco",
    howSub:
      "Pensada para organizadores e jogadores de padel e outros esportes: convocações, confirmações e quem já contribuiu.",
    point1Title: "Organize",
    point1Body:
      "Monte o encontro, convide o roster e veja quem confirmou, quem falta ou quem está na reserva.",
    point2Title: "Administre cobranças",
    point2Body:
      "Registre quem pagou, guarde comprovantes (fotos) e acompanhe saldos do grupo no app.",
    point3Title: "Sem gateway de pagamento",
    point3Body:
      "A Kloovi não cobra jogadores nem recebe transferências. O dinheiro circula fora do app, entre vocês.",
    calloutTitle: "Importante para a Play Store e usuários",
    calloutBody:
      "A Kloovi <strong>não é um aplicativo financeiro</strong>. Não é carteira, banco, processador de pagamentos nem intermediário de dinheiro. Só armazena informação administrativa e comprovantes que organizador ou jogador enviam para controlar o grupo.",
    contactTitle: "Contato",
    contactSub: "Dúvidas de privacidade, conta ou publicação?",
    footerCopy: "© {year} Kloovi · kloovi.app",
    privacyH1: "Política de Privacidade",
    privacyMeta: "Última atualização: 13 de julho de 2026 · Responsável: Kloovi (kloovi.app)",
    termsH1: "Termos de Serviço",
    termsMeta: "Última atualização: 13 de julho de 2026 · Kloovi (kloovi.app)",
    backHome: "← Kloovi",
    privacyHtml: `
      <div class="notice">
        <strong>Kloovi não é um app financeiro</strong>
        A Kloovi não recebe, custodia, transfere nem processa dinheiro. Não somos banco, carteira digital, processador de pagamentos (PSP) nem intermediário de cobranças. O app só ajuda a organizar partidas e a <em>administrar</em> informações de cobrança do grupo. Qualquer pagamento real ocorre fora da Kloovi, entre organizador e jogadores.
      </div>
      <p>Esta Política explica quais dados pessoais tratamos ao usar o app Kloovi e o site <a href="https://kloovi.app">kloovi.app</a>. Contato de privacidade: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>1. Quem somos</h2>
      <p>Kloovi é um app de organização esportiva e administração de gastos/cobranças de grupos. O responsável pelo tratamento é o operador da Kloovi, no e-mail acima.</p>
      <h2>2. Quais dados tratamos</h2>
      <ul>
        <li><strong>Conta e identidade:</strong> nome, e-mail, foto de perfil (ex.: Google), ID de usuário.</li>
        <li><strong>Uso do grupo:</strong> partidas, convocações, confirmações, roster, saldos e rótulos administrativos.</li>
        <li><strong>Comprovantes:</strong> imagens/arquivos de um pagamento feito <em>fora</em> do app. A Kloovi não executa o pagamento.</li>
        <li><strong>Dispositivo e notificações:</strong> token FCM, idioma/preferências, diagnósticos se habilitados.</li>
        <li><strong>Suporte:</strong> conteúdo que você enviar por e-mail.</li>
      </ul>
      <p>Não pedimos dados de cartão, senhas bancárias, CVV ou credenciais de gateways, porque a Kloovi <strong>não processa pagamentos</strong>.</p>
      <h2>3. Finalidades</h2>
      <ul>
        <li>Criar e autenticar contas (incluindo Google).</li>
        <li>Organizar partidas, convites, confirmações e comunicação do grupo.</li>
        <li>Permitir ao organizador administrar cobranças (registros, saldos e revisão de comprovantes).</li>
        <li>Enviar notificações do app, se você permitir.</li>
        <li>Segurança, prevenção de abuso e estabilidade.</li>
        <li>Cumprir obrigações legais aplicáveis.</li>
      </ul>
      <h2>4. Bases do tratamento</h2>
      <p>Tratamos dados para prestar o serviço, com consentimento quando aplicável, e por interesse legítimo de segurança e melhoria.</p>
      <h2>5. Fornecedores</h2>
      <ul>
        <li><strong>Supabase</strong> — autenticação, banco e armazenamento.</li>
        <li><strong>Google</strong> — Login com Google, FCM e Analytics/Crashlytics se habilitados.</li>
        <li><strong>Vercel</strong> — hospedagem deste site.</li>
      </ul>
      <p>Não vendemos seus dados pessoais.</p>
      <h2>6. Comprovantes e “não somos app financeiro”</h2>
      <p>Um comprovante é evidência administrativa de pagamento externo. A Kloovi não inicia transferências, não recebe fundos, não remete dinheiro, não é gateway/carteira e não garante cobrança entre particulares.</p>
      <h2>7. Conservação</h2>
      <p>Mantemos dados enquanto a conta existir e for necessário ao serviço. Pedidos de exclusão: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>8. Segurança</h2>
      <p>Aplicamos medidas razoáveis (controle de acesso, HTTPS). Nenhum sistema é 100% seguro.</p>
      <h2>9. Seus direitos</h2>
      <p>Conforme a lei aplicável, você pode solicitar acesso, retificação, oposição, limitação ou exclusão, e retirar consentimentos. E-mail: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>10. Menores</h2>
      <p>A Kloovi não é direcionada a menores de 13 anos (ou idade mínima da sua jurisdição).</p>
      <h2>11. Transferências internacionais</h2>
      <p>Fornecedores podem processar dados fora do seu país, com as salvaguardas que oferecerem.</p>
      <h2>12. Alterações</h2>
      <p>A versão vigente será publicada em <a href="https://kloovi.app/privacy">kloovi.app/privacy</a>.</p>
      <h2>13. Contato</h2>
      <p>Privacidade: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a><br />Site: <a href="https://kloovi.app">https://kloovi.app</a></p>
    `,
    termsHtml: `
      <div class="notice">
        <strong>Declaração-chave (Google Play / usuários)</strong>
        A Kloovi <strong>não é um aplicativo financeiro</strong>. Não oferece serviços bancários, crédito, remessas, investimento, cripto nem processamento de pagamentos. <strong>A Kloovi não recebe dinheiro</strong>. Só permite registrar e administrar cobranças do grupo e receber <strong>comprovantes</strong> (ex.: fotos) para controle interno. Pagamentos reais ocorrem fora do app.
      </div>
      <p>Ao usar a Kloovi ou <a href="https://kloovi.app">kloovi.app</a>, você aceita estes Termos. Contato: <a href="mailto:hello@kloovi.app">hello@kloovi.app</a>.</p>
      <h2>1. Descrição do serviço</h2>
      <ul>
        <li>Organizar partidas e convites/confirmações.</li>
        <li>Manter um roster de jogadores.</li>
        <li>Registrar contribuições, saldos e rótulos do grupo.</li>
        <li>Anexar e revisar comprovantes de pagamentos externos.</li>
      </ul>
      <h2>2. O que a Kloovi não é</h2>
      <ul>
        <li>Não somos instituição financeira nem emissora de meios de pagamento.</li>
        <li>Não recebemos, custodiamos nem transferimos fundos.</li>
        <li>Não iniciamos débitos em cartões.</li>
        <li>Não somos gateway, agregador, carteira nem escrow.</li>
        <li>Não garantimos pagamentos entre particulares nem mediamos juridicamente a cobrança.</li>
      </ul>
      <p>Qualquer pagamento ocorre fora da Kloovi, entre as pessoas do grupo.</p>
      <h2>3. Comprovantes</h2>
      <p>Arquivos (em geral fotos) como evidência de pagamento externo. O organizador decide como validá-los. A Kloovi não verifica autenticidade bancária automática.</p>
      <h2>4. Contas</h2>
      <p>Informações verdadeiras; idade mínima legal (pelo menos 13 anos). Pode haver papéis jogador/organizador e, no futuro, assinaturas de software do organizador (não serviço financeiro).</p>
      <h2>5. Conduta</h2>
      <p>Não use a Kloovi para fraude, lavagem de dinheiro, assédio ou outras ilegalidades; não apresente o app como banco ou processador de pagamentos.</p>
      <h2>6. Conteúdo do usuário</h2>
      <p>Você mantém direitos sobre o que envia; concede licença limitada para operar o serviço. Ver <a href="/privacy">Privacidade</a>.</p>
      <h2>7. Notificações e permissões</h2>
      <p>Push e câmera/galeria apenas com sua permissão.</p>
      <h2>8. Assinaturas (se houver)</h2>
      <p>Cobrança de software ao organizador não é cobrança “em nome” dos jogadores nem produto financeiro.</p>
      <h2>9. Disponibilidade</h2>
      <p>Serviço “no estado em que se encontra” e conforme disponibilidade.</p>
      <h2>10. Limitação de responsabilidade</h2>
      <p>A Kloovi não responde por disputas de pagamento entre usuários nem por reservas externas. Nada limita direitos inalienáveis do consumidor quando a lei proíbe.</p>
      <h2>11. Propriedade intelectual</h2>
      <p>Marca e software Kloovi pertencem aos seus titulares.</p>
      <h2>12. Encerramento</h2>
      <p>Você pode parar de usar o app; podemos suspender contas que violem estes Termos.</p>
      <h2>13. Privacidade</h2>
      <p>Regida pela <a href="/privacy">Política de Privacidade</a>.</p>
      <h2>14. Lei aplicável</h2>
      <p>Leis do Chile, sem prejuízo de normas imperativas da sua residência.</p>
      <h2>15. Contato</h2>
      <p><a href="mailto:hello@kloovi.app">hello@kloovi.app</a> · <a href="https://kloovi.app">kloovi.app</a></p>
    `,
  },
};
