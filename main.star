NAME_ARG = "name"
USER_ARG = "user"
PASSWORD_ARG = "password"
ROOT_USER_ARG = "root_user"
ROOT_PASSWORD_ARG = "root_password"
IMAGE_ARG = "image"
ENV_VARS_ARG = "env_vars"
DB_NAME_ARG = "dbname"

PORT_NAME = "mongodb"
PORT_NUMBER = 27017
PROTOCOL_NAME = "mongodb"

SNAPSHOT_FILES_SOURCE_PATH = "github.com/kurtosis-tech/novu-import-example/static-files"
SNAPSHOT_FILES_LABEL = "mongodb_snapshot_files"
SNAPSHOT_FILES_TARGET_PATH = "/opt/mongodb/snapshots"


def run(plan, args):
    service_name = args.get(NAME_ARG, "mongodb")
    image = args.get(IMAGE_ARG, "mongo:6.0.5")
    root_user = args.get(ROOT_USER_ARG, "root")
    root_password = args.get(ROOT_PASSWORD_ARG, "password")
    user = args.get(USER_ARG, "root")
    password = args.get(PASSWORD_ARG, "password")
    dbname = args.get(DB_NAME_ARG, "")
    env_var_overrides = args.get(ENV_VARS_ARG, {})

    env_vars = {
        "MONGO_INITDB_ROOT_USERNAME": root_user,
        "MONGO_INITDB_ROOT_PASSWORD": root_password,
        "PUID": "1000",
        "PGID": "1000",
    }
    env_vars |= env_var_overrides

    plan.upload_files(
        src=SNAPSHOT_FILES_SOURCE_PATH,
        name=SNAPSHOT_FILES_LABEL
    )

    # Add the server
    service = plan.add_service(
        name=service_name,
        config=ServiceConfig(
            image=image,
            ports={
                PORT_NAME: PortSpec(
                    number=PORT_NUMBER,
                    application_protocol=PROTOCOL_NAME
                ),
            },
            env_vars=env_vars,
            files={
                SNAPSHOT_FILES_TARGET_PATH: SNAPSHOT_FILES_LABEL
            }
        ),
    )

    url = "{protocol}://{user}:{password}@{hostname}:{port}/{dbname}".format(
        protocol = PROTOCOL_NAME,
        user = user,
        password = password,
        hostname = service.hostname,
        port = PORT_NUMBER,
        dbname = dbname
    )

    # If database is set, create a new database with custom user
    if dbname != '':
        # Create user
        create_user(plan, service_name, dbname, user, password, root_user, root_password)

        # If there are dumped collections in static-files dir, then
        restore_collection(plan, service_name, dbname, user, password)

    return struct(
        service=service,
        url=url,
    )

def create_user(plan, service_name, dbname, user, password, root_user, root_password):
    command_create_user = "db.getSiblingDB('%s').createUser({user:'%s', pwd:'%s', roles:[{role:'readWrite',db:'%s'}]});" % (
        dbname, user, password, dbname
    )
    exec_create_user = ExecRecipe(
        command=[
            "mongosh",
            "-u",
            root_user,
            "-p",
            root_password,
            "-eval",
            command_create_user
        ],
    )

    plan.wait(
        service_name=service_name,
        recipe=exec_create_user,
        field="code",
        assertion="==",
        target_value=0,
        timeout="30s",
    )

def restore_collection(plan, service_name, dbname, user, password):
    collection_name = "messagetemplates"
    exec_load_dump = ExecRecipe(
        command=[
            "mongoimport",
            "-u",
            user,
            "-p",
            password,
            "-d",
            dbname,
            "-c",
            collection_name,
            "--file",
            "%s/%s.%s.json" % (SNAPSHOT_FILES_TARGET_PATH, dbname, collection_name),
            "--jsonArray"
        ],
    )

    plan.wait(
        service_name=service_name,
        recipe=exec_load_dump,
        field="code",
        assertion="==",
        target_value=0,
        timeout="30s",
    )