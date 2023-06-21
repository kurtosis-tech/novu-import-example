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

def run(plan, args):
    service_name = args.get(NAME_ARG, "mongodb")
    image = args.get(IMAGE_ARG, "mongo:6.0.5")
    root_user = args.get(ROOT_USER_ARG, "root")
    root_password = args.get(ROOT_PASSWORD_ARG, "password")
    user = args.get(USER_ARG, "root")
    password = args.get(PASSWORD_ARG, "password")
    dbname = args.get(DB_NAME_ARG, "")
    env_var_overrides = args.get(ENV_VARS_ARG, {
        "PUID": "1000",
        "PGID": "1000",
    })

    env_vars = {
        "MONGO_INITDB_ROOT_USERNAME": root_user,
        "MONGO_INITDB_ROOT_PASSWORD": root_password,
    }
    env_vars |= env_var_overrides

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

    if dbname != '':
        mongodb_local_url = "mongodb://localhost:%d/%s" % (PORT_NUMBER, dbname)

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

        command_create_collection = "db.getSiblingDB('%s').createCollection('%s');" % (
            dbname, dbname
        )

        exec_create_collection = ExecRecipe(
            command=[
                "mongosh",
                mongodb_local_url,
                "-u",
                user,
                "-p",
                password,
                "-eval",
                command_create_collection
            ],
        )

        plan.wait(
            service_name=service_name,
            recipe=exec_create_collection,
            field="code",
            assertion="==",
            target_value=0,
            timeout="30s",
        )

    return struct(
        service=service,
        url=url,
    )
