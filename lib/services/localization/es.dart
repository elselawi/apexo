import 'en.dart';

class Es implements En {
  @override
  Direction $direction = Direction.ltr;
  @override
  String $name = "Español";
  @override
  String $code = "es";

  @override
  Map<String, String> dictionary = {
    // common
    "cancel": "Cancelar",
    "close": "Cerrar",
    "save": "Guardar",
    "reset": "Restablecer",
    "continue": "Continuar",
    "add": "Añadir",
    "edit": "Editar",
    "delete": "Eliminar",
    "deletedItems": "Eliminados",
    "deleted": "Eliminado",
    "archive": "Archivar",
    "restore": "Restaurar",
    "logout": "Cerrar sesión",
    "VoiceInput": "Entrada de voz",
    "noResultsFound": "No se encontraron resultados",
    "startTyping": "Empieza a escribir",
    "home": "Inicio",
    "calendar": "Calendario",
    "gettingImages": "Obteniendo imágenes",
    "more": "Más",
    "howToUse": "Cómo usar",

    // new
    "newPatient": "Nuevo paciente",
    "newAppointment": "Nueva cita",
    "newLabwork": "Nuevo caso",
    "newNote": "Nueva nota",
    "newUser": "Nuevo usuario",
    "newAdmin": "Nuevo administrador",

    // screens
    "settings": "Configuraciones",
    "dashboard": "Tablero",
    "appointments": "Citas",
    "patients": "Pacientes",
    "doctors": "Doctores",
    "labworks": "trabajos de lab.",
    "insights": "Análisis",

    // dashboard
    "admin": "Admin",
    "payments": "Pagos",
    "appointmentsToday": "Citas hoy",
    "patientsToday": "Pacientes hoy",
    "newPatientsToday": "Nuevos pacientes hoy",
    "paymentsMadeToday": "Pagos realizados hoy",
    "modeAdmin": "ADMIN modo",
    "modeUser": "USUARIO modo",
    "modeOffline": "FUERA DE LÍNEA modo",
    "onceConnectionIsStable":
        "Una vez que tu conexión sea estable, puedes usar el botón en la esquina superior derecha para reconectar.",
    "unRestrictedAccess": "acceso sin restricciones en la aplicación",
    "restrictedAccess":
        "acceso restringido a algunas pantallas según lo dictado por el administrador",
    "youAreCurrentlyIn": "Actualmente estás en",
    "mode": "modo",
    "youHave": "Tienes",
    "hello": "Hola",

    // datatable
    "archiveSelected": "Archivar seleccionados",
    "searchPlaceholder": "Buscar...",
    "showHideArchived": "Mostrar/Ocultar archivados",
    "showing": "Mostrando",
    "showMore": "Ver más",
    "by": "Por",
    "byName": "Por nombre",
    "noItemsFound": "No se encontraron elementos",
    "filter": "Filtrar",

    // doctors
    "doctor": "Doctor",
    "pastAppointments": "Citas pasadas",
    "upcomingAppointments": "Próximas citas",
    "viewAllAppointments": "Ver todas las citas",
    "otherAppointments": "Otras citas",
    "addAppointment": "Añadir cita",

    // days and months
    "monday": "Lunes",
    "tuesday": "Martes",
    "wednesday": "Miércoles",
    "thursday": "Jueves",
    "friday": "Viernes",
    "saturday": "Sábado",
    "sunday": "Domingo",

    // appointment card
    "appointment": "Cita",
    "patient": "Paciente",
    "photos": "Fotos",
    "pre-opNotes": "Notas preoperatorias",
    "post-opNotes": "Notas postoperatorias",
    "prescription": "Receta",
    "pay": "Pagar",
    "paid": "Pagado",
    "price": "Precio",
    "underpaid": "Insuficientemente pagado",
    "overpaid": "Excesivamente pagado",
    "fullyPaid": "Completamente pagado",
    "includesOtherAppointments":
        "Este total también refleja los pagos de otras citas.",
    "paymentSummary": "Resumen de pagos",
    "after": "Después",
    "days": "días",
    "day": "día",
    "isDone": "La cita está completada",
    "addLabwork":
        "Agregar trabajo de laboratorio para esta cita y este paciente",
    "labworksForThisAppointment": "Trabajo de laboratorio para esta cita",

    // patients
    "patientDetails": "Detalles del paciente",
    "age": "Edad",
    "gender": "Género",
    "lastVisit": "Última visita",
    "nextVisit": "Próxima visita",
    "totalPayments": "Pagos totales",
    "daysAgo": "días atrás",
    "noVisits": "Sin visitas",
    "name": "Nombre",
    "birthYear": "Año de nacimiento",
    "phone": "Teléfono",
    "noValidNumbersFound": "No se encontraron números de teléfono válidos",
    "theFollowingPhoneNumbersAreDetected":
        "Solo se detectaron los siguientes números de teléfono",
    "email": "Correo electrónico",
    "address": "Dirección",
    "notes": "Notas",
    "patientTags": "Etiquetas del paciente",
    "male": "Masculino",
    "female": "Femenino",
    "noAppointmentsFound":
        "No se encontraron citas para este paciente, utiliza el botón de abajo para agregar una nueva cita.",
    "patientPage": "Página web del paciente",
    "patientCanUseTheFollowing":
        "El paciente puede usar el siguiente enlace para acceder a sus citas, pagos y fotos.",
    "printQR": "Imprimir código QR",
    "web": "Web",
    "telegram": "Telegram",
    "dentalNotes": "Notas dentales",
    "showPrimary": "Mostrar principal",
    "showPermanent": "Mostrar permanente",
    "primary": "Principal",
    "permanent": "Permanente",
    "lower": "Inferior",
    "upper": "Superior",
    "left": "Izquierda",
    "right": "Derecha",
    "centralIncisor": "Incisivo central",
    "lateralIncisor": "Incisivo lateral",
    "canine": "Canino",
    "firstPremolar": "Primer premolar",
    "secondPremolar": "Segundo premolar",
    "firstMolar": "Primer molar",
    "secondMolar": "Segundo molar",
    "thirdMolar": "Tercer molar",
    "exportSelected": "Exportar seleccionados",
    "export": "Exportar",
    "exportImportFeatureExplanation":
        "Para mover los datos seleccionados de pacientes y citas entre servidores u otras aplicaciones, exporta un CSV desde el servidor de origen e impórtalo al servidor o aplicación de destino.",
    "qrCode": "Código QR",
    "share": "Compartir",
    "otherPhotos": "Fotos de otras citas",
    "draw": "Dibujar",
    "erase": "Borrar",
    "showDrawings": "Mostrar dibujos",

    // communication
    "contact": "Contact",
    "sendEmail": "Enviar correo",
    "whatsapp": "WhatsApp",
    "call": "Llamar",
    "text": "Mensaje",
    "countryCode": "Código de país",
    "countryCode_desc":
        "Selecciona el código de país predeterminado al realizar llamadas o enviar mensajes",

    // treatments
    "treatment": "Tratamiento",
    "allTreatments": "Todos",
    "extraction": "Extracción",
    "filling": "Obturación",
    "pulpotomy": "Pulpotomía",
    "rCT": "Endodoncia",
    "other": "Otro",
    "re-RCT": "Reendodoncia",
    "ortho": "Ortodoncia",
    "whitening": "Blanque",
    "clean": "Limpieza",
    "implant": "Implante",
    "surgery": "Cirugía",
    "crown": "Corona",
    "veneer": "Carilla",
    "bridge": "Puente",
    "overlay": "Overlay",
    "temporary": "Temporal",
    "tap the treatment you have performed to register it to the tooth":
        "Toca el tratamiento realizado para registrarlo en el diente",
    "tap the condition or history of the tooth to register it":
        "Toque la condición o el historial del diente para registrarlo",
    "missing": "Ausente",
    "caries": "Caries",
    "fractured": "Fracturado",
    "mobility": "Movilidad",
    "recession": "Recesión",
    "rroot": "R. Radicular",
    "rprimary": "R. Primario",
    "malposition": "Malposición",
    "impacted": "Impactado",
    "abutment": "Pilar",
    "pontic": "Póntico",

    // calendar (appointments)
    "allDoctors": "Todos los doctores",
    "noAppointmentsForThisDay": "No hay citas para este día",
    "weekAbbr": "S",
    "twoWeeksAbbr": "2S",
    "monthAbbr": "M",
    "min": "min",
    "minutes": "minutos",
    "duration": "Duración",
    "today": "Hoy",
    "switchToTimelineView": "Cambiar a vista de línea de tiempo",
    "switchToAgendaView": "Cambiar a vista de agenda",
    "date": "Fecha",
    "changeDate": "Cambiar fecha",
    "changeTime": "Cambiar hora",
    "time": "Hora",
    "preOperativeNotes": "Notas preoperatorias",
    "selectDoctors": "Seleccionar doctores",
    "selectPatient": "Seleccionar paciente",
    "operativeDetails": "Detalles operativos",
    "postOperativeNotes": "Notas postoperatorias",
    "extraInfoPlaceholder": "Info adicional",
    "extraNotesFromAppointments": "Notas adicionales de citas:",
    "otherAppointmentsNotes": "Notas de otras citas:",
    "printPrescription": "Imprimir receta",
    "priceIn": "Precio en",
    "paidIn": "Pagado en",
    "gallery": "Galería",
    "link": "Enlace",
    "upload": "Subir",
    "camera": "Cámara",
    "emptyGallery": "Galería vacía",
    "noPhotos": "No se han subido fotos todavía.",
    "importingPhotosFromLink": "Importando fotos desde el enlace",
    "useThisForm":
        "Usa este formulario para importar fotos desde enlaces compartidos, como Google Fotos, o cualquier página web accesible que contenga fotos que desees añadir a esta cita.",
    "error": "Error",
    "enterLink": "Ingresa una URL que contenga fotos",
    "import": "Importar",

    // labworks
    "laboratory": "Laboratorio",
    "month": "mes",
    "labwork": "Trabajo",
    "orderNotes": "Notas del pedido",
    "noSuggestions": "Sin sugerencias",
    "received": "Recibido del laboratorio",
    "showDone": "Mostrar completados",
    "waitingForLab": "Esperando al laboratorio",
    "undelivered": "No entregado al paciente",
    "receivedAndDelivered": "Recibido y entregado",
    "selectPatientFirst": "Seleccione un paciente primero",
    "patientHasNoAppointments": "El paciente no tiene citas",
    "selectAppointment": "Seleccione una cita",
    "areYouSureYouWantTo": "¿Está seguro de que desea",
    "youCanRestoreFromDeletedItemsPage":
        "Puede restaurarlo desde la página de elementos eliminados",
    "youWillNotBeAbleToRestore": "No podrá restaurarlo",

    // expenses
    "expense": "Gasto",
    "expenses": "Gastos",
    "receipt": "Recibo",
    "title": "Título",
    "cost": "Costo",
    "amount": "Cantidad",
    "status": "Estado",
    "due": "Vencido",
    "open": "Abrir",
    "rename": "Cambiar nombre",
    "addSupplier": "Agregar proveedor",
    "items": "Ítems",
    "markAsPaid": "Marcar como pagado",
    "markAsDue": "Marcar como pendiente",
    "addOrder": "Agregar pedido",
    "new": "Nuevo",
    "thisMonth": "Este mes",
    "addPhoto": "Agregar foto",
    "files": "Archivos",
    "noFiles": "Aún no se han agregado archivos.",
    "change": "Cambiar",
    "empty": "Vacío",
    "totalDue": "Total pendiente",
    "notSet": "No establecido",
    "photo": "Foto",
    "viewAllOrders": "Ver todos los pedidos",
    "lastOrder": "Ultimo pedido",
    "supplier": "Proveedor",
    "order": "Pedido",
    "orders": "Pedidos",

    // notes
    "addColumn": "Agregar columna",
    "editColumn": "Editar columna",
    "columnTitle": "Título de la columna",
    "columnColor": "Color de la columna",
    "addNote": "Agregar nota",
    "editNote": "Editar nota",
    "note": "Nota",
    "recurrence": "Recurrencia",
    "isARecurrenceOfOlderNote": "Es una recurrencia de una nota anterior",
    "recurringEvery": "Recurrente cada",
    "recurring": "Recurrente",
    "column": "Columna",
    "uncategorized": "Sin categoría",
    "relatingToPatient": "Relacionado con el paciente",
    "assignedTo": "Asignado a",
    "dueDate": "Vence",
    "attachments": "Adjuntos",
    "deleteAllCompletedNotes": "Eliminar todas las notas completadas",
    "moveTowardsEnd": "Mover hacia el final",
    "moveTowardsStart": "Mover hacia el inicio",
    "item": "Ítem",
    "addAttachment": "Agregar adjunto",
    "tapToDownload": "Toque para descargar",
    "addComment": "Agregar comentario",
    "sendComment": "Enviar comentario",
    "tapToMarkAsPending": "Toque para marcar como pendiente",
    "tapToMarkAsDone": "Toque para marcar como completado",
    "archived": "Archivado",
    "noDeletedItems": "No hay elementos eliminados",
    "overdue": "Vencido",
    "incoming": "Entrante",
    "outgoing": "Saliente",
    "pending": "Pendiente",
    "completed": "Completado",
    "unassigned": "Sin asignar",
    "comments": "Comentarios",
    "createdDate": "Creación",
    "changeDueDate": "Cambiar fecha de vencimiento",
    "createdBy": "Creado por",
    "switchAssignee": "Cambiar asignado",
    "noAssignee": "Sin asignado",
    "sort": "Ordenar",
    "ascending": "ascendente",
    "descending": "descendente",
    "showAll": "Mostrar todo",
    "allAccounts": "Todas las cuentas",

    // stats
    "pickRange": "Seleccionar rango",
    "pickPhotos": "Seleccionar fotos",
    "pickFiles": "Seleccionar archivos",
    "photoSlideshow": "Presentación de fotos",
    "start": "Inicio",
    "end": "Fin",
    "weeks": "Semanas",
    "months": "Meses",
    "quarters": "Trimestres",
    "years": "Años",
    "year": "Año",
    "appointmentsPer": "Citas por",
    "paymentsAndExpensesPer": "Pagos y gastos por",
    "newPatientsPer": "Nuevos pacientes por",
    "doneMissedPer": "Realizadas y perdidas por",
    "timeOfDay": "Hora del día",
    "dayOfWeek": "Día de la semana",
    "dayOfMonth": "Día del mes",
    "monthOfYear": "Mes del año",
    "patientsGender": "Género de los pacientes",
    "total": "Total",
    "in_Duration_": "en",
    "acquiredPatientsIn": "Pacientes adquiridos en",
    "doneAndMissedAppointmentsIn": "Citas realizadas y perdidas en",
    "distributionOfAppointments": "Distribución de citas",
    "maleAndFemalePatients": "Pacientes masculinos y femeninos",
    "done": "realizado",
    "missed": "perdido",
    "periodicity": "Periodicidad",

    // settings
    "currency": "Moneda",
    "currency_desc":
        "Código de moneda a usar en toda la aplicación (p. ej., USD, EUR, IQD).",
    "phone_desc":
        "El número de teléfono se mostrará en impresiones y en la página web del paciente.",
    "prescriptionFooter": "Pie de página de la receta",
    "prescriptionFooter_desc": "Este texto se mostrará al final de la receta.",
    "language": "Idioma",
    "language_desc":
        "El idioma de la interfaz para los menús, botones e información usada en toda la aplicación.",
    "startingDayOfWeek": "Primer día de la semana",
    "startingDayOfWeek_desc": "El día de la semana en que comienza la semana.",
    "dateFormat": "Formato de fecha",
    "calendarView": "Vista de calendario",
    "calendarView_desc": "Elige cómo se muestran las citas en el calendario.",
    "agenda": "Agenda (lista)",
    "timeline": "Línea de tiempo (cuadrícula)",
    "dateFormat_desc":
        "Este formato se usará para mostrar fechas cuando aplique.",
    "cacheReset": "Reiniciar caché",
    "cacheReset_desc":
        "Puedes usar el siguiente botón para reiniciar el caché de la aplicación, excepto las imágenes. Esto puede ayudar a resolver algunos problemas que podrías estar teniendo al sincronizar con otros dispositivos.",
    "month/day/year": "Mes/Día/Año",
    "day/month/year": "Día/Mes/Año",
    "appliesTo": "Aplica a",
    "all": "Todos",
    "you": "tú", "system": "sistema",
    "initialSynchronization": "Sincronización inicial",
    "synchronizing": "Sincronizando",
    "clearingLocalData": "Limpiando datos locales",
    "dentalNotation": "Notación dental",
    "dentalNotation_desc": "Elija su sistema de notación preferido",
    "palmer": "Palmer",
    "universal": "Universal",
    "ISO": "ISO",

    // advanced settings: Backups
    "backup": "Copia de seguridad",
    "backups": "Copias de seguridad",
    "refresh": "Actualizar",
    "download": "Descargar",
    "createNew": "Crear nueva",
    "restoreBackup": "Restaurar copia de seguridad",
    "restoreBackupWarning1":
        "Restaurar esta copia de seguridad sobrescribirá todos los datos actuales en la aplicación. Cualquier cambio que hayas hecho después de la fecha de esta copia de seguridad",
    "restoreBackupWarning2":
        "se perderá.\n\n¿Estás seguro de que deseas restaurar esta copia de seguridad?",
    "sureDeleteBackup":
        "¿Estás seguro de que deseas eliminar esta copia de seguridad?",
    "backupDate": "Fecha de la copia de seguridad",
    "useTheFollowingLinkToDownloadTheBackup":
        "Usa el siguiente enlace para descargar la copia de seguridad",
    "backups_config_title": "Configuración de copias de seguridad",
    "backups_config_desc":
        "Configura el programa de copias de seguridad automáticas y el almacenamiento.",
    "backups_auto_enabled": "Activar copias automáticas",
    "backups_cron": "Programación (cron)",
    "backups_cron_presets": "Preajustes",
    "backups_cron_hourly": "Cada hora",
    "backups_cron_6hours": "Cada 6 horas",
    "backups_cron_12hours": "Cada 12 horas",
    "backups_cron_daily": "Diario a medianoche",
    "backups_cron_daily3am": "Diario a las 3 AM",
    "backups_cron_weekly": "Semanal (dom. medianoche)",
    "backups_cron_monthly": "Mensual (día 1 medianoche)",
    "backups_cron_hint":
        "Selecciona una programación predefinida. La expresión cron se completa automáticamente.",
    "backups_max_keep": "Máximo de copias a conservar",
    "backups_max_keep_hint":
        "Las copias más antiguas se eliminarán al superar este límite",
    "backups_s3_enabled": "Guardar copias en S3",
    "backups_save_success": "Configuración de copias guardada correctamente",
    "backups_save_fail": "Error al guardar la configuración de copias",

    // Meta settings
    "meta_settings": "Configuración de la aplicación",
    "meta_info_title": "Información general de la aplicación",
    "meta_info_desc":
        "Configura el nombre de tu aplicación, URL y ajustes de marca.",
    "meta_appName": "Nombre de la aplicación",
    "meta_appName_hint":
        "Se muestra en los correos electrónicos y en el título de inicio de sesión",
    "meta_appUrl": "URL de la aplicación",
    "meta_appUrl_hint": "Se usa en correos electrónicos y enlaces compartidos",
    "meta_save_success":
        "Configuración de la aplicación guardada correctamente",
    "meta_save_fail": "Error al guardar la configuración de la aplicación",

    // Auth settings
    "auth_settings": "Configuración de autenticación",
    "auth_info_title": "Duración de sesión",
    "auth_info_desc":
        "Establece cuánto tiempo permanecen válidos los tokens antes de que los usuarios deban iniciar sesión nuevamente.",
    "auth_users_duration": "Sesión de usuario (días)",
    "auth_users_duration_hint":
        "Cuántos días antes de que los usuarios regulares necesiten re-iniciar sesión",
    "auth_superusers_duration": "Sesión de administrador (días)",
    "auth_superusers_duration_hint":
        "Cuántos días antes de que los administradores necesiten re-iniciar sesión",
    "auth_save_success":
        "Configuración de autenticación guardada correctamente",
    "auth_save_fail": "Error al guardar la configuración de autenticación",

    // File upload settings
    "file_upload_settings": "Configuración de subida de archivos",
    "file_upload_info_title": "Tamaño máximo de subida de archivos",
    "file_upload_info_desc":
        "Establezca el tamaño máximo permitido para la subida de archivos (imágenes, documentos, etc.) en toda la aplicación.",
    "file_upload_max_size": "Tamaño máximo de archivo (MB)",
    "file_upload_max_size_hint":
        "Tamaño máximo en megabytes para cada archivo subido",
    "file_upload_save_success":
        "Configuración de subida de archivos guardada correctamente",
    "file_upload_save_fail":
        "Error al guardar la configuración de subida de archivos",

    // advanced settings: Admins
    "admins": "Administradores",
    "validEmailMustBeProvided":
        "Debe proporcionarse un correo electrónico válido",
    "password": "Contraseña",
    "leaveBlankToKeepUnchanged": "Deja en blanco para mantener sin cambios",
    "updatingPassword": "Actualizando contraseña",
    "leaveItEmpty": "Deja el campo de contraseña vacío si no deseas cambiarlo.",
    "minimumPasswordLength": "Contraseña de al menos 10 caracteres",

    // advanced settings: Users
    "users": "Usuarios",

    // advanced settings: Permissions
    "permissions": "Permisos de usuario",
    "restricted": "Restringido",
    "view": "Ver",
    "personal": "Personal",
    "full": "Completo",
    "local": "Local",
    "canUpload": "Puede subir",
    "cantUpload": "No puede subir",
    "revenue": "Ingresos",
    "canSee": "Puede ver",
    "canNotSee": "No puede ver",
    "accounts": "Cuentas",
    "account": "Cuenta",
    "user": "Usuario",
    "operatesOnPatients": "Opera a pacientes",

    // S3 settings
    "s3_settings": "Configuración de almacenamiento S3",
    "s3_info_title": "Configurar almacenamiento S3",
    "s3_info_desc":
        "Configura tus ajustes de almacenamiento compatible con S3 para cargas de archivos y copias de seguridad.",
    "s3_endpoint": "URL del punto final",
    "s3_bucket": "Nombre del bucket",
    "s3_region": "Región",
    "s3_accessKey": "Clave de acceso",
    "s3_secretKey": "Clave secreta",
    "s3_secretKey_hint":
        "Déjalo vacío para mantenerlo sin cambios. Tu clave de acceso secreta S3",
    "s3_enabled": "Habilitar almacenamiento S3",
    "s3_forcePathStyle": "Forzar estilo de ruta",
    "s3_forcePathStyle_hint":
        "Usar direccionamiento de estilo ruta en lugar de subdominio (necesario para Cloudflare R2)",
    "s3_endpoint_hint": "URL del punto final de tu proveedor S3",
    "s3_bucket_hint": "El nombre de tu bucket S3",
    "s3_region_hint": "Región del bucket, o 'auto' para Cloudflare R2",
    "s3_accessKey_hint": "Tu ID de clave de acceso S3",
    "s3_test_success": "La configuración de S3 está funcionando correctamente",
    "s3_test_fail": "La prueba de configuración de S3 falló",
    "s3_save_success": "Configuración de S3 guardada correctamente",
    "s3_save_fail": "Error al guardar la configuración de S3",
    "test": "Probar",

    // SMTP settings
    "smtp_settings": "Configuración SMTP",
    "smtp_info_title": "Configurar correo SMTP",
    "smtp_info_desc":
        "Configura tus ajustes SMTP para enviar correos electrónicos (restablecimiento de contraseñas, notificaciones, etc.).",
    "smtp_host": "Servidor",
    "smtp_port": "Puerto",
    "smtp_username": "Usuario",
    "smtp_password": "Contraseña",
    "smtp_senderName": "Nombre del remitente",
    "smtp_senderEmail": "Correo del remitente",
    "smtp_tls": "Usar TLS",
    "smtp_tls_auto": "Auto (STARTTLS)",
    "smtp_tls_always": "Siempre",
    "smtp_tls_hint":
        "Auto = STARTTLS (puerto 587)\n Siempre = SSL (puerto 465)",
    "smtp_presets": "Preajustes",
    "smtp_port_blocked_warning":
        "Algunos proveedores cloud (ej. DigitalOcean, Hetzner, Google Cloud) bloquean los puertos SMTP por defecto. Asegúrate de que 587 o 465 estén permitidos.",
    "smtp_host_hint": "Dirección del servidor SMTP de tu proveedor de correo",
    "smtp_port_hint": "587 o 465",
    "smtp_username_hint": "Generalmente tu dirección de correo completa",
    "smtp_password_hint":
        "Déjalo vacío para mantenerlo sin cambios. Usa una contraseña de aplicación si 2FA está activado",
    "smtp_app_passwords": "Contraseñas de aplicación",
    "smtp_senderName_hint": "Nombre mostrado en el campo De",
    "smtp_senderEmail_hint": "Dirección de correo mostrada en el campo De",
    "smtp_localName": "Nombre local HELO/EHLO",
    "smtp_localName_hint":
        "Usado en el saludo HELO/EHLO, generalmente tu dominio",
    "smtp_enabled": "Habilitar SMTP",
    "smtp_test_success": "La configuración SMTP está funcionando correctamente",
    "smtp_test_fail": "La prueba de configuración SMTP falló",
    "smtp_save_success": "Configuración SMTP guardada correctamente",
    "smtp_save_fail": "Error al guardar la configuración SMTP",

    "fail": "Fallar",
    "success": "Éxito",

    // login
    "login": "Iniciar sesión",
    "clear": "Limpiar",
    "resetPassword": "Restablecer contraseña",
    "serverUrl": "URL del servidor",
    "proceedOffline": "Proceder fuera de línea",
    "youLLGet": "Obtendrás el enlace de restablecimiento por correo",
    "beenSent":
        "Instrucciones para restablecer la contraseña han sido enviadas, revisa tu bandeja de entrada.",

    // static notifications flyout
    "notifications": "Notificaciones",
    "enableNotifications": "Habilitar notificaciones",
    "dueLabworks": "Análisis pendientes",
    "undeliveredLabworks": "Análisis no entregados",
    "outgoingNotes": "Notas salientes",
    "incomingNotes": "Notas entrantes",
    "appointmentsSetToday": "citas de hoy",
    "labworksDue": "análisis pendientes",
    "labworksNotDelivered": "análisis no entregados",
    "outgoingPendingNotes": "notas salientes pendientes",
    "incomingPendingNotes": "notas entrantes pendientes",

    // patientSide
    "generateQRLink": "Generar enlace QR",
    "patientSide": "Panel del paciente",

    // other
    "sureClosePanel":
        "¿Estás seguro de que deseas cerrar el panel? Todos los cambios no guardados se perderán.",
    "sure": "Seguro",
    "back": "Regresar",
    "firstLaunchDialogTitle": "Bienvenido a Apexo",
    "firstLaunchDialogContent":
        "Has instalado Apexo exitosamente. Sin embargo, para una mejor experiencia y para uso real, tendrás un par de cosas que configurar. Escanea el código QR de abajo para comenzar.",
    "newVersionDialogTitle": "Nueva versión disponible",
    "newVersionDialogContent":
        "Una nueva versión de Apexo está disponible. Por favor actualiza a la última versión para obtener la mejor experiencia. Escanea el código QR de abajo para comenzar.",

    // login required
    "loginRequired": "Se requiere inicio de sesión",
    "loginRequiredDesc": "Por favor inicia sesión para continuar",

    // server help flyout
    "whatIsAServer": "¿Qué es un servidor?",
    "helpOnCreatingAServer":
        "Un servidor permite que tus datos se almacenen de forma segura, se hagan copias de seguridad, se sincronicen entre dispositivos y más.",
    "createNewServer": "Crear nuevo servidor",

    // when errors:
    "errors": "Errores",
    "reconnect": "Reconectar",
    "uploadingAttachment": "subiendo archivo adjunto",
    "errorHappenedWhen": "Ocurrió un error al",
    "deletingPatientImageFromServer":
        "eliminar la imagen del paciente del servidor",
    "importingRemoteImages": "importar imágenes remotas",
    "creatingNewAccount": "crear una nueva cuenta",
    "updatingAccounts": "actualizar cuentas",
    "deletingAccount": "eliminar la cuenta",
    "uploadingPatientImageFromCamera":
        "subir la imagen del paciente desde la cámara",
    "uploadingPatientImageFromGallery":
        "subir la imagen del paciente desde la galería",
    "deletingOrderImageFromServer":
        "eliminar la imagen de la orden del servidor",
    "uploadingOrderImageFromGallery":
        "subir la imagen de la orden desde la galería",
    "uploadingOrderImageFromCamera":
        "subir la imagen de la orden desde la cámara",
    "openingImageFromGrid": "abrir la imagen desde la cuadrícula",
    "openingMultipleImagesFromGrid": "abrir las imágenes desde la cuadrícula",
    "generatingPatientLink": "generando enlace del paciente",
    "gettingRemoteImagesList": "obteniendo lista de imágenes remotas",
    "sendingUpdatesToServer": "enviando actualizaciones al servidor",
    "deletingFile": "eliminando archivo",
    "uploadingFile": "subiendo archivo",

    // AI services
    "ai_services": "Servicios de IA",
    "ai_services_desc":
        "Activar o desactivar funciones impulsadas por IA como escaneo de recibos, notas de voz y extracción de historial dental.",
    "on": "Activado",
    "off": "Desactivado",
    "sameAsAppLanguage": "Igual que el idioma de la app",
    "audioTranscriptionLocale": "Idioma de transcripción de audio",
    "audioTranscriptionLocale_desc":
        "Por defecto, las transcripciones de audio se traducen al idioma actual de la aplicación. Puedes elegir un idioma diferente si lo necesitas.",
    "no_training_privacy_info":
        "Cuando activas estas funciones, tus archivos se procesan de forma privada. Nunca los almacenamos después del procesamiento — se leen solo en memoria para tu solicitud (como bytes en flujo) y se descartan inmediatamente. Tus datos nunca se usan para entrenar IA.",

    // Receipt scanner
    "scanReceipt": "Escanear Recibo",
    "readFromPhoto": "Leer desde foto",
    "readingItemsFromPhoto": "leyendo artículos desde la foto",
    "receiptScanFailed": "Error al escanear recibo",
    "testing": "Probando conexión...",
    "unknown": "Desconocido",
    "unidentified": "No identificado",

    // Dental history recording
    "VoiceAutoFill": "Autocompletar por voz",
    "dentalHistoryVoiceAutoFillHint":
        "Dicta los números y condiciones dentales de forma natural para actualizar la ficha del paciente automáticamente.",
    "postOperativeVoiceAutoFillHint":
        "Resume la visita. Dicta tu registro, notas post-operatorias, recetas, honorarios o trabajos de laboratorio para completar cada formulario automáticamente.",
    "transcribingYourAudio": "Transcribiendo tu audio...",
    "recording": "Grabando",
    "paused": "Pausado",
    "processingDentalHistory": "procesando historial dental",
    "processingPostOpNotes": "procesando notas post-operatorias",

    // calendar system
    "calendarSystem": "Sistema de calendario",
    "calendarSystem_desc":
        "Elija el sistema de calendario para mostrar las fechas",
    "gregorian": "Gregoriano",
    "persian": "Persa (Jalali / Shamsi)",

    // Jalali month names
    "farvardin": "Farvardin",
    "ordibehesht": "Ordibehesht",
    "khordad": "Khordad",
    "tir": "Tir",
    "mordad": "Mordad",
    "shahrivar": "Shahrivar",
    "mehr": "Mehr",
    "aban": "Aban",
    "azar": "Azar",
    "dey": "Dey",
    "bahman": "Bahman",
    "esfand": "Esfand",
  };
}
